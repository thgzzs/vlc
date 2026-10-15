param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$VideoFixture,
    [switch]$TestOnboarding,
    [switch]$RequireAccessibleHeadings,
    [switch]$DeepFeatures,
    [switch]$TestWaveform,
    [switch]$TestLibraryTools
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
    if ($DeepFeatures) { $clientArguments += '-DeepFeatures' }
    if ($TestWaveform) { $clientArguments += '-TestWaveform' }
    if ($TestLibraryTools) { $clientArguments += '-TestLibraryTools' }
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
$pcm = New-Object byte[] (8000 * 2 * 120)
# Deterministic PCM envelope: silent / 25% / 75% / silent quarters.
# Alternate signed samples so every active block has a known exact peak.
$quarterBytes = [int]($pcm.Length / 4)
[byte[]]$mediumTone = [byte[]](@(0,32,0,224) * 4000)
[byte[]]$loudTone = [byte[]](@(0,96,0,160) * 4000)
for ($offset = 0; $offset -lt $quarterBytes; $offset += $mediumTone.Length) {
    [Buffer]::BlockCopy($mediumTone,0,$pcm,$quarterBytes+$offset,$mediumTone.Length)
    [Buffer]::BlockCopy($loudTone,0,$pcm,2*$quarterBytes+$offset,$loudTone.Length)
}
$writer = [IO.BinaryWriter]::new([IO.File]::Create($fixture))
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $pcm.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([int]16)
    $writer.Write([int16]1)
    $writer.Write([int16]1)
    $writer.Write([int]8000)
    $writer.Write([int]16000)
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
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string device, int mode, ref VlcDisplayMode settings);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int ChangeDisplaySettings(ref VlcDisplayMode settings, uint flags);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")]
    public static extern uint GetDoubleClickTime();
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
# Onboarding must change the initial theme; otherwise a preseeded Dark value
# would make the persistence assertion pass without exercising theme selection.
$initialTheme = if ($TestOnboarding) { 1 } else { 2 }
"[MainWindow]`ncolor-scheme-index=$initialTheme`nnavigation-panel-visible=true`nnavigation-panel-width=200" |
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
    Save-ShutdownDiagnostics
    throw "Expected $Expected; last observation: $last"
}

function Wait-VideoDecoderReady([int]$ItemId) {
    # PLAYING is player-wide and can still describe the preceding input while
    # the next file opens. A pause request before its decoder starts can be
    # ignored. Require real decoded frames from the selected input first.
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $state = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($state.currentplid -eq $ItemId -and $state.state -eq 'playing' -and
            $state.stats.decodedvideo -gt 0 -and $state.time -ge 0.2 -and $state.time -lt 5) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    Save-ShutdownDiagnostics
    throw "Video input $ItemId did not become decoder-ready before pausing"
}

function Press-Control($Window, [string]$Name, [Windows.Automation.ControlType]$Type = $null, [switch]$Pointer) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
    $buttons = $Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    foreach ($button in $buttons) {
        if ($Type -and $button.Current.ControlType -ne $Type) { continue }
        if ($button.Current.IsOffscreen -or !$button.Current.IsEnabled) { continue }
        if ($Pointer -or $button.Current.ControlType -in @([Windows.Automation.ControlType]::CheckBox, [Windows.Automation.ControlType]::TabItem, [Windows.Automation.ControlType]::ListItem)) {
            $bounds = $button.Current.BoundingRectangle
            if ($bounds.Top -lt 0 -or $bounds.Bottom -gt $desktopHeight -or $bounds.Right -gt $desktopWidth) { throw "$Name is outside the clickable desktop" }
            # A quick seek can complete before Windows' double-click interval.
            # Qt MouseArea consumes that second click as a double-click instead
            # of two single-click actions. Exercise distinct human clicks.
            if ($script:lastPointerClick) {
                $remainingMs = [VlcGuiWindow]::GetDoubleClickTime() + 50 - ([DateTime]::UtcNow - $script:lastPointerClick).TotalMilliseconds
                if ($remainingMs -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Ceiling($remainingMs)) }
            }
            [VlcGuiWindow]::SetCursorPos([int]($bounds.X + $bounds.Width/2), [int]($bounds.Y + $bounds.Height/2)) | Out-Null
            [VlcGuiWindow]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
            [VlcGuiWindow]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
            $script:lastPointerClick = [DateTime]::UtcNow
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

function Wait-VisibleControl($Window, [string]$Name, [Windows.Automation.ControlType]$Type = $null) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        try {
            $element = @($Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object {
                !$_.Current.IsOffscreen -and (!$Type -or $_.Current.ControlType -eq $Type)
            }) | Select-Object -Last 1
            if ($element) { return $element }
        } catch {
            # Qt replaces accessible providers as a native file picker closes.
            # Retry observation within the same deadline; a process exit still fails.
            $proc.Refresh()
            if ($proc.HasExited) { throw "VLC exited while waiting for ${Name}: exit code $($proc.ExitCode)" }
            $lastObservationError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "No visible native control: ${Name}; last UIA error: $lastObservationError"
}

function Scroll-ToControl([string]$Name, [Windows.Automation.ControlType]$Type = $null) {
    $bounds = $window.Current.BoundingRectangle
    [VlcGuiWindow]::SetCursorPos([int]($bounds.Right - 40), [int]($bounds.Top + 300)) | Out-Null
    for ($up=0; $up -lt 8; ++$up) {
        [VlcGuiWindow]::mouse_event(0x0800,0,0,720,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
    }
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,$Name)
    for ($down=0; $down -lt 14; ++$down) {
        $found = @($window.FindAll([Windows.Automation.TreeScope]::Descendants,$condition) | Where-Object {
            !$_.Current.IsOffscreen -and (!$Type -or $_.Current.ControlType -eq $Type)
        }) | Select-Object -Last 1
        if ($found) { return $found }
        [VlcGuiWindow]::mouse_event(0x0800,0,0,[uint32]4294966816,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 120
    }
    throw "No scroll-reachable native control: $Name"
}

function Wait-Timing([double]$Rate,[double]$AudioDelay,[double]$SubtitleDelay) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $state = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ([Math]::Abs($state.rate-$Rate) -lt 0.01 -and [Math]::Abs($state.audiodelay-$AudioDelay) -lt 0.01 -and
            [Math]::Abs($state.subtitledelay-$SubtitleDelay) -lt 0.01) { return $state }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timing did not become rate=$Rate audio=$AudioDelay subtitle=$SubtitleDelay; observed rate=$($state.rate) audio=$($state.audiodelay) subtitle=$($state.subtitledelay)"
}

function Advance-AndVerifySeek([double]$ExpectedSeconds) {
    # A paused input can retain the previous decoder clock after a seek.
    # VLC's native E/next-frame hotkey presents one decoded frame while staying
    # paused. This avoids letting a slow UIA/HTTP round trip overshoot the cue.
    Wait-PlaybackState 'paused' | Out-Null
    [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
    [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x45, [IntPtr]::Zero) | Out-Null
    [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x45, [IntPtr]::Zero) | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $status = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($status.state -ne 'paused') { throw 'Native next-frame unexpectedly resumed playback' }
        if ([Math]::Abs($status.position * $status.length - $ExpectedSeconds) -le 0.75) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ([Math]::Abs($status.position * $status.length - $ExpectedSeconds) -gt 0.75) {
        throw "Decoded frame seek did not reach ${ExpectedSeconds}s: position=$($status.position), length=$($status.length)"
    }
    return $status
}

function Record-Check([string]$Name, $Details, [string]$Status = 'passed') {
    $script:completedChecks += @{ check=$Name; status=$Status; details=$Details }
    $script:completedChecks | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'completed-checks.json')
    Write-Host "Check: $Name; status=$Status"
    if ($Status -eq 'failed') { Write-Host ($Details | ConvertTo-Json -Depth 8 -Compress) }
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

function Test-ThemeSelected($Window, [string]$Name) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
    $matches = @($Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object { !$_.Current.IsOffscreen })
    # The custom tab list exposes the current theme as its accessible name.
    # Some Windows providers expose SelectionItem for the child but always
    # report false; read the live tab-list binding as well.
    foreach ($element in $matches) {
        if ($element.Current.ControlType -eq [Windows.Automation.ControlType]::Tab) { return $true }
        if ($element.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem -and (Test-TabSelected $element)) { return $true }
    }
    return $false
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

$script:completedChecks = @()
$featureErrors = @()
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
    Record-Check 'native Qt startup' @{seconds=$startupSeconds}
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
        # Reopen without forcing the wizard flag. Verify both persisted theme
        # state in the real settings page and that onboarding does not repeat.
        $restartArguments = @($arguments | Where-Object { $_ -ne '--qt-privacy-ask' })
        $proc = Start-Process $exe.FullName -ArgumentList $restartArguments -WorkingDirectory $exe.DirectoryName -PassThru `
            -RedirectStandardOutput (Join-Path $OutputDirectory 'restart-stdout.txt') `
            -RedirectStandardError (Join-Path $OutputDirectory 'restart-stderr.txt')
        $restartDeadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            $proc.Refresh()
            if ($proc.HasExited) { throw 'VLC exited during the persisted-theme restart' }
            if ($proc.MainWindowHandle -ne 0) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $restartDeadline)
        if ($proc.MainWindowHandle -eq 0) { throw 'No Qt window after onboarding restart' }
        $mainWindowHandle = $proc.MainWindowHandle
        $window = [Windows.Automation.AutomationElement]::FromHandle($mainWindowHandle)
        [VlcGuiWindow]::SetWindowPos($mainWindowHandle, [IntPtr]::Zero, 20, 20, $wideWidth, $wideHeight, 0x14) | Out-Null
        [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
        Wait-VisibleControl $window 'Main interface' | Out-Null
        Start-Sleep -Milliseconds 500
        $reopenedWizard = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $welcomeCondition) | Where-Object { !$_.Current.IsOffscreen })
        if ($reopenedWizard.Count) { throw 'Onboarding reopened after Finish saved its completion state' }
        Press-Control $window 'Extended settings'
        Press-Control $window 'Open Advanced Settings'
        Press-Control $window 'General' ([Windows.Automation.ControlType]::TabItem)
        Wait-VisibleControl $window 'Global Settings' | Out-Null
        if (!(Test-ThemeSelected $window 'Dark')) { throw 'The restarted application did not restore Dark theme' }
        Save-WindowScreenshot $window 'qt-onboarding-restarted-dark.png'
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        Close-NativeWindow $window
        if (!$proc.WaitForExit(60000)) { Save-ShutdownDiagnostics; throw 'Restarted onboarding process did not shut down cleanly' }
        if ($proc.ExitCode -ne 0) { throw "Onboarding restart returned $($proc.ExitCode)" }
        $onboardingQmlErrors = Select-String -Path (Join-Path $OutputDirectory '*stderr.txt') -Pattern 'ReferenceError:|TypeError:|is not a type|failed to load component'
        if ($onboardingQmlErrors) { throw ($onboardingQmlErrors | Out-String) }
        Record-Check 'onboarding finish and persisted appearance after restart' 'Dark selected from Light; wizard completed once; two clean native exits'
        @{ status='passed'; onboarding='welcome, theme, shortcuts, finish, restart and persisted Dark theme'; native_shutdown='two clean exits'; startup_seconds=$startupSeconds } |
            ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'results.json')
        return
    }
    $volumeCheck = 'not run (video-only fixture has no audio track)'
    if (!$VideoFixture) {
        $volumeSlider = Wait-VisibleControl $window 'Volume' ([Windows.Automation.ControlType]::Slider)
        $initialVolume = (Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3).volume
        if ($initialVolume -lt 0) {
            $volumeCheck = 'unverified: dummy audio output has no volume_set/mute_set callbacks'
            Record-Check 'native volume control' $volumeCheck 'unverified'
        } else {
        $volumeSlider.SetFocus()
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        $changedVolume = (Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3).volume
        if ($changedVolume -ge $initialVolume) { throw 'Native volume keyboard action did not lower the VLC audio output' }
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x26, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x26, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        $restoredVolume = (Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3).volume
        if ([Math]::Abs($restoredVolume - $initialVolume) -gt 2) { throw 'Native volume slider did not restore the original level' }
        $volumeCheck = 'native slider updated and restored the real audio-output volume'
        Record-Check 'native volume control' @{changed=$changedVolume; restored=$restoredVolume}
        }
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
    Record-Check 'native play/pause and seeking' @{position=$seekStatus.position}

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
    Record-Check 'resizing and playlist switching' @{previous=$previousStatus.currentplid; next=$nextStatus.currentplid}
    if ($TestWaveform -and !$VideoFixture) {
        # Playlist selection and PLAYING can precede the new input's decoder.
        # Require decoded audio near its beginning before asking it to pause.
        $inputDeadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $inputReady = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            if ($inputReady.currentplid -eq $initial.currentplid -and $inputReady.stats.decodedaudio -gt 0 -and
                $inputReady.time -ge 0.2 -and $inputReady.time -lt 5) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $inputDeadline)
        if ($inputReady.currentplid -ne $initial.currentplid -or $inputReady.stats.decodedaudio -le 0 -or $inputReady.time -lt 0.2 -or $inputReady.time -ge 5) {
            throw 'The restored audio input did not become decoder-ready before waveform testing'
        }
        Write-Host 'Waveform test: pausing the decoder-ready main input'
        Press-Control $window 'Play/Pause' 
        $waveformBefore = Wait-PlaybackState 'paused'
        Press-Control $window 'Extended settings'
        Press-Control $window 'Audio Waveform'
        Wait-VisibleControl $window 'Waveform ready, peak 75%' ([Windows.Automation.ControlType]::Text) | Out-Null
        Wait-VisibleControl $window 'Audio amplitude waveform' | Out-Null
        $waveformAfter = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($waveformAfter.state -ne 'paused' -or $waveformAfter.currentplid -ne $waveformBefore.currentplid -or
            [Math]::Abs($waveformAfter.position - $waveformBefore.position) -gt 0.01) {
            throw 'Background waveform analysis changed the primary player state or position'
        }
        Save-WindowScreenshot $window 'qt-waveform-generated.png'
        Press-Control $window 'Audio Waveform'
        Press-Control $window 'Audio Waveform'
        Wait-VisibleControl $window 'Waveform ready, peak 75%' ([Windows.Automation.ControlType]::Text) | Out-Null
        $cacheLog = Select-String -Path (Join-Path $OutputDirectory 'stderr.txt') -SimpleMatch 'waveform: cache hit'
        if (!$cacheLog) { throw 'Re-enabling the waveform did not reuse its bounded cache' }
        # Keep waveform enabled while changing input. A new waveform must replace
        # the old one; native controls and the main audio player must still work.
        Press-Control $window 'Next' -Pointer
        Wait-PlaybackState 'playing' $waveformBefore.currentplid $true | Out-Null
        Press-Control $window 'Extended settings'
        Wait-VisibleControl $window 'Waveform ready, peak 75%' ([Windows.Automation.ControlType]::Text) | Out-Null
        Save-WindowScreenshot $window 'qt-waveform-switched-media.png'
        Press-Control $window 'Audio Waveform'
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        Record-Check 'native PCM waveform, exact peak, cache reuse and media switching' @{peak_percent=75; primary_player_unchanged=$true}
    }
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
        Record-Check 'video decode, F/Escape fullscreen and native seek preview' $seekPreviewCheck
        $bounds = $window.Current.BoundingRectangle
        [VlcGuiWindow]::SetCursorPos([int]($bounds.X + 50), [int]($bounds.Y + 80)) | Out-Null
        # Keep the fixture paused throughout the modal checks. A short looping
        # clip can switch inputs while the settings and profile tests run.
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
            if ($name -eq 'Show Metadata') {
                $textCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Text)
                $rightEdge = $window.Current.BoundingRectangle.Right
                $sourceText = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $textCondition) | Where-Object {
                    !$_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Left -gt $rightEdge - 430 -and
                    $_.Current.Name -like ('file://*' + [IO.Path]::GetFileName($fixture))
                }) | Select-Object -First 1
                if (!$sourceText) { throw 'Metadata did not render the current media source URL' }
                Save-WindowScreenshot $window 'qt-live-metadata.png'
                Record-Check 'native media metadata' $sourceText.Current.Name
            }
            if ($name -eq 'Show Statistics') {
                # Accessible activation keeps the panel open; a real pointer
                # press on the bar dismisses it and disables live statistics.
                Press-Control $window 'Play/Pause'
                Wait-PlaybackState 'playing' | Out-Null
                Start-Sleep -Milliseconds 1500
                Press-Control $window 'Play/Pause'
                Wait-PlaybackState 'paused' | Out-Null
                $statisticsDeadline = [DateTime]::UtcNow.AddSeconds(5)
                do {
                    $nativeStatistics = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
                    $count = [string]$nativeStatistics.stats.decodedvideo
                    $valueCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $count)
                    $renderedCount = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $valueCondition) | Where-Object {
                        !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Text -and
                        $_.Current.BoundingRectangle.Left -gt $window.Current.BoundingRectangle.Right - 430
                    }) | Select-Object -First 1
                    if ($nativeStatistics.stats.decodedvideo -gt 0 -and $renderedCount) { break }
                    Start-Sleep -Milliseconds 200
                } while ([DateTime]::UtcNow -lt $statisticsDeadline)
                if ($nativeStatistics.stats.decodedvideo -le 0 -or !$renderedCount) { throw 'Statistics did not render the native decoded-video counter' }
                Save-WindowScreenshot $window 'qt-live-statistics.png'
                Record-Check 'native decoder statistics' @{decoded_video=$nativeStatistics.stats.decodedvideo; rendered_value=$renderedCount.Current.Name}
            }
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
            if ($RequireAccessibleHeadings -and $category.Key -ne 'General') {
                # Follow the actual category keyboard navigation. UIA can call
                # clipped lower tabs "onscreen" while their click is intercepted
                # by the fixed footer. Down selects and reveals the next tab.
                [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
                [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
            } else {
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
            }
            Start-Sleep -Milliseconds 400
            $titleCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $category.Value)
            $title = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $titleCondition) | Where-Object { !$_.Current.IsOffscreen }) | Select-Object -First 1
            if (!$title) {
                if ($RequireAccessibleHeadings) { throw "Settings category did not expose its rendered heading: $($category.Key)" }
                # Diagnostic runs of older packages can still capture all pages.
                # Missing headings remain explicitly unverified, never passed.
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
                if (!(Test-ThemeSelected $window 'Light')) { throw 'Light theme did not become selected before applying the saved profile' }
                Save-WindowScreenshot $window 'qt-profile-before-apply-light.png'
                Press-Control $window 'Apply Application Profile'
                Start-Sleep -Milliseconds 500
                $darkCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Dark')
                $dark = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $darkCondition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem }) | Select-Object -First 1
                if (!$dark) { throw 'No native Dark theme selection' }
                if (!(Test-ThemeSelected $window 'Dark')) { throw 'Application profile did not restore the saved Dark theme' }
                Save-WindowScreenshot $window 'qt-profile-after-apply-dark.png'
                Press-Control $window 'Delete Application Profile'
                $applicationProfileCheck = 'saved defaults, changed theme, restored the saved theme and removed the disposable profile'
                if ($RequireAccessibleHeadings) {
                    $generalTab = Wait-VisibleControl $window 'General' ([Windows.Automation.ControlType]::TabItem)
                    $generalTab.SetFocus()
                }
            }
            Save-WindowScreenshot $window ('qt-settings-' + $category.Key.ToLowerInvariant() + '.png')
            $settingsChecks += $category.Key
            Record-Check ('settings category ' + $category.Key) @{accessible_heading=[bool]$title} $(if ($title) { 'passed' } else { 'unverified' })
        }
        # Exercise native keyboard focus and Escape dismissal of the modal.
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x09, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x09, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 200
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x1b, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        $searchCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Search settings')
        $stillOpen = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $searchCondition) | Where-Object { !$_.Current.IsOffscreen })
        if ($stillOpen.Count) { throw 'Escape did not dismiss the settings modal' }
        $playbackToolsChecks = 'native subtitle timeline, sleep timer, metadata and statistics toggles passed'
        Record-Check 'application profiles and settings keyboard dismissal' $applicationProfileCheck
    }
    if ($VideoFixture -and $DeepFeatures) {
        $deepStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($deepStatus.state -eq 'playing') {
            Press-Control $window 'Play/Pause' -Pointer
            Wait-PlaybackState 'paused' | Out-Null
        }
        Press-Control $window 'Menu'
        Press-Control $window 'Customize Player'
        $customProfile = Wait-VisibleControl $window 'Profile' ([Windows.Automation.ControlType]::ComboBox)
        Save-WindowScreenshot $window 'qt-customize-player.png'
        $customDragOk = $false
        if ($TestLibraryTools) {
            try {
            $saveLayout = Wait-VisibleControl $window 'Save' ([Windows.Automation.ControlType]::Button)
            if ($saveLayout.Current.IsEnabled) { throw 'The toolbar editor unexpectedly opened with unsaved changes' }
            $customTitle = Wait-VisibleControl $window 'Customize Player' ([Windows.Automation.ControlType]::TitleBar)
            $nextCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,'Next')
            $windowBounds = $window.Current.BoundingRectangle
            $nextTarget = @($window.FindAll([Windows.Automation.TreeScope]::Descendants,$nextCondition) | Where-Object {
                !$_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Bottom -gt ($windowBounds.Bottom-90)
            }) | Select-Object -Last 1
            if (!$nextTarget) { throw 'No native toolbar drop target in the customizer' }
            # Palette tiles are visually rendered MouseAreas, without UIA text
            # children. This fixture's observed Stop tile is index 5 in row 1.
            # Anchor its actual pointer position to the native header and the
            # checked QML metrics: padding 34, cell 110, tile 86, header 94.
            $scale = $customProfile.Current.BoundingRectangle.Height/32
            $startX = $customTitle.Current.BoundingRectangle.Left+608*$scale
            $startY = $customProfile.Current.BoundingRectangle.Top+135*$scale
            $targetBounds = $nextTarget.Current.BoundingRectangle
            if ($startX -ge $windowBounds.Right -or $startY -ge $windowBounds.Bottom-100) {
                throw 'The observed customization palette geometry is outside this test window'
            }
            Write-Host "Native palette drag: source=($startX,$startY), target=($($targetBounds.Right-3),$($targetBounds.Y+$targetBounds.Height/2))"
            $endX = $targetBounds.Right-3
            $endY = $targetBounds.Y+$targetBounds.Height/2
            [VlcGuiWindow]::SetCursorPos([int]$startX,[int]$startY) | Out-Null
            [VlcGuiWindow]::mouse_event(0x02,0,0,0,[UIntPtr]::Zero)
            try {
                for ($step=1; $step -le 14; ++$step) {
                    [VlcGuiWindow]::SetCursorPos([int]($startX+($endX-$startX)*$step/14),[int]($startY+($endY-$startY)*$step/14)) | Out-Null
                    Start-Sleep -Milliseconds 45
                }
            } finally { [VlcGuiWindow]::mouse_event(0x04,0,0,0,[UIntPtr]::Zero) }
            $script:lastPointerClick = [DateTime]::UtcNow
            $dragDeadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                if ($saveLayout.Current.IsEnabled) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $dragDeadline)
            if (!$saveLayout.Current.IsEnabled) { throw 'Native palette drag did not change the editable toolbar model' }
            Save-WindowScreenshot $window 'qt-customize-player-after-drag.png'
            $customDragOk = $true
            } catch {
                $featureErrors += $_.Exception.Message
                Record-Check 'native toolbar drag' $_.Exception.Message 'failed'
                try { Save-WindowScreenshot $window 'qt-customize-drag-failure.png' } catch { }
            }
        }
        Press-Control $window 'Cancel'
        if ($TestLibraryTools) {
            $stopCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,'Stop')
            $remainingStop = @($window.FindAll([Windows.Automation.TreeScope]::Descendants,$stopCondition) | Where-Object {
                !$_.Current.IsOffscreen -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button
            })
            if ($remainingStop.Count) { throw 'Cancel did not restore the toolbar after the native drag' }
            if ($customDragOk) { Record-Check 'native toolbar drag changes the editable model and Cancel restores the saved profile' @{save_enabled_after_drag=$true; restored=$true} }
        }
        Record-Check 'native player customization opens and cancels' 'Existing toolbar profile was preserved'

        Press-Control $window 'Extended settings'
        Press-Control $window 'Subtitles' ([Windows.Automation.ControlType]::TabItem)
        Press-Control $window 'Show Subtitle Timeline'
        # The native file picker runs a modal event loop. InvokePattern waits
        # for its handler to return, so use real input to leave this client free
        # to operate the picker while it is open.
        Press-Control $window 'Add Subtitle File' -Pointer
        $pickerCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Open subtitles...')
        $dialogDeadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            $fileDialog = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $pickerCondition) | Where-Object {
                !$_.Current.IsOffscreen
            }) | Select-Object -First 1
            if ($fileDialog) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $dialogDeadline)
        if (!$fileDialog) { throw 'Native subtitle file dialog did not open' }
        # GitHub runner paths can contain mixed separators. The Windows shell
        # picker rejects forward slashes in its file-name field.
        $subtitleFile = [IO.Path]::GetFullPath([IO.Path]::ChangeExtension($VideoFixture, '.srt')).Replace('/', '\')
        if (!(Test-Path -LiteralPath $subtitleFile)) { throw 'The native subtitle fixture path does not exist' }
        # Qt's UIA bridge exposes the native picker edit as a Pane. Use the
        # Windows file-name accelerator and paste the exact local fixture path.
        Set-Clipboard -Value $subtitleFile
        [VlcGuiWindow]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x4e, 0, 0, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x4e, 0, 2, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x56, 0, 0, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x56, 0, 2, [UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
        Press-Control $fileDialog 'Open' -Pointer
        Wait-VisibleControl $window 'Native VLC subtitle test' ([Windows.Automation.ControlType]::ListItem) | Out-Null
        Wait-VisibleControl $window 'Second subtitle cue' ([Windows.Automation.ControlType]::ListItem) | Out-Null
        Press-Control $window 'Second subtitle cue'
        $cueStatus = Advance-AndVerifySeek 4.5
        Save-WindowScreenshot $window 'qt-subtitle-cues.png'
        $cueStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'subtitle-seek-status.json')
        Record-Check 'native subtitle picker, SRT parsing and cue seeking' @{time=$cueStatus.time; cues=2}

        try {
            Press-Control $window 'Play Queue'
            Press-Control $window 'Bookmarks' ([Windows.Automation.ControlType]::TabItem)
            Press-Control $window 'Add a bookmark' -Pointer
            $bookmarkDeadline = [DateTime]::UtcNow.AddSeconds(10)
            $listItemCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::ListItem)
            do {
                $bookmark = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $listItemCondition) | Where-Object {
                    !$_.Current.IsOffscreen -and $_.Current.Name -like 'Bookmark at *'
                }) | Select-Object -First 1
                if ($bookmark) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $bookmarkDeadline)
            if (!$bookmark) { throw 'Adding a bookmark did not create a persistent row' }
            $bookmarkName = $bookmark.Current.Name
            # Select for deletion without also seeking: row activation queues a
            # decoder-clock update, which is unrelated to the Ctrl+B test below.
            $bookmark.SetFocus()
            Press-Control $window 'Remove a bookmark' -Pointer
            $removedCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $bookmarkName)
            $removeDeadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                $removedRows = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $removedCondition) | Where-Object { !$_.Current.IsOffscreen })
                if (!$removedRows.Count) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $removeDeadline)
            if ($removedRows.Count) { throw 'The first bookmark deletion did not complete before Ctrl+B' }
            [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
            [VlcGuiWindow]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
            [VlcGuiWindow]::keybd_event(0x42, 0, 0, [UIntPtr]::Zero)
            [VlcGuiWindow]::keybd_event(0x42, 0, 2, [UIntPtr]::Zero)
            [VlcGuiWindow]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
            # Ctrl+B captures the current clock, so its name need not equal the
            # deleted bookmark's timestamp. Require a newly created named row.
            $bookmarkDeadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                $bookmark = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $listItemCondition) | Where-Object {
                    !$_.Current.IsOffscreen -and $_.Current.Name -like 'Bookmark at *'
                }) | Select-Object -First 1
                if ($bookmark) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $bookmarkDeadline)
            if (!$bookmark) { throw 'Ctrl+B did not create a named bookmark row' }
            $bookmarkName = $bookmark.Current.Name
            $bookmarkStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            $bookmarkSeconds = $bookmarkStatus.position * $bookmarkStatus.length
            Save-WindowScreenshot $window 'qt-bookmark-created.png'
            Record-Check 'named bookmark add, remove and Ctrl+B recreation' @{name=$bookmarkName; item=$bookmarkStatus.currentplid}
            Press-Control $window 'Next' -Pointer
            $bookmarkOther = Wait-PlaybackState 'playing' $bookmarkStatus.currentplid $true
            Wait-VideoDecoderReady $bookmarkOther.currentplid
            Press-Control $window 'Play/Pause' -Pointer
            Wait-PlaybackState 'paused' | Out-Null
            # A bar click dismisses the sidebar. Reopen it explicitly so absence
            # is checked in a visible bookmark list, not in a hidden panel.
            Press-Control $window 'Play Queue' -Pointer
            Press-Control $window 'Bookmarks' ([Windows.Automation.ControlType]::TabItem)
            $bookmarkCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $bookmarkName)
            $stale = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $bookmarkCondition) | Where-Object { !$_.Current.IsOffscreen })
            if ($stale.Count) { throw 'Previous media bookmark remained visible after switching media' }
            Save-WindowScreenshot $window 'qt-bookmark-other-media.png'
            Press-Control $window 'Previous' -Pointer
            Wait-PlaybackState 'playing' $bookmarkStatus.currentplid | Out-Null
            Wait-VideoDecoderReady $bookmarkStatus.currentplid
            Press-Control $window 'Play/Pause' -Pointer
            Wait-PlaybackState 'paused' | Out-Null
            Press-Control $window 'Play Queue' -Pointer
            Press-Control $window 'Bookmarks' ([Windows.Automation.ControlType]::TabItem)
            Wait-VisibleControl $window $bookmarkName ([Windows.Automation.ControlType]::ListItem) | Out-Null
            Save-WindowScreenshot $window 'qt-bookmark-restored.png'
            Press-Control $window $bookmarkName
            $bookmarkSeek = Advance-AndVerifySeek $bookmarkSeconds
            # Native frame advance preserves the selected bookmark panel.
            Wait-VisibleControl $window $bookmarkName ([Windows.Automation.ControlType]::ListItem) | Out-Null
            Press-Control $window 'Remove a bookmark' -Pointer
            Start-Sleep -Milliseconds 500
            $remaining = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $bookmarkCondition) | Where-Object { !$_.Current.IsOffscreen })
            if ($remaining.Count) { throw 'Removing the bookmark left its row visible' }
            Record-Check 'bookmarks, Ctrl+B, seeking and media-switch isolation' @{time=$bookmarkSeek.time}
        } catch {
            $featureErrors += $_.Exception.Message
            Record-Check 'bookmarks, Ctrl+B, seeking and media-switch isolation' $_.Exception.Message 'failed'
            try { Save-WindowScreenshot $window 'qt-bookmark-failure.png' } catch { }
        }

        if ($TestLibraryTools) {
            $matchingFolder = Join-Path $OutputDirectory 'matching-subtitles'
            New-Item -ItemType Directory -Force $matchingFolder | Out-Null
            $subtitleSource = [IO.Path]::ChangeExtension($VideoFixture,'.srt')
            Copy-Item $subtitleSource (Join-Path $matchingFolder 'video-fixture.srt') -Force
            Copy-Item $subtitleSource (Join-Path $matchingFolder 'video-fixture.en.srt') -Force
            Copy-Item $subtitleSource (Join-Path $matchingFolder 'next-fixture.srt') -Force
            $beforeMatch = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            Press-Control $window 'Extended settings'
            Press-Control $window 'Subtitles' ([Windows.Automation.ControlType]::TabItem)
            Press-Control $window 'Match Queue Subtitles'
            $folderField = Wait-VisibleControl $window 'Subtitle Matching Folder' ([Windows.Automation.ControlType]::Edit)
            $folderField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue((Join-Path $OutputDirectory 'missing-subtitle-folder'))
            Press-Control $window 'Scan Queue Subtitle Matches'
            Wait-VisibleControl $window 'Choose an existing local subtitle folder.' ([Windows.Automation.ControlType]::Text) | Out-Null
            $saveMatches = Wait-VisibleControl $window 'Save Selected Subtitle Matches' ([Windows.Automation.ControlType]::Button)
            if ($saveMatches.Current.IsEnabled) { throw 'An invalid subtitle folder left matching results applicable' }
            Record-Check 'invalid subtitle folder reports an error and disables save' @{save_enabled=$false}
            $folderField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($matchingFolder.Replace('/','\'))
            Press-Control $window 'Scan Queue Subtitle Matches'
            Wait-VisibleControl $window '2 queue items · 1 ready · 1 ambiguous. Review before applying.' ([Windows.Automation.ControlType]::Text) | Out-Null
            Save-WindowScreenshot $window 'qt-subtitle-matches-review.png'
            # The ambiguous first item remains skipped until explicit selection.
            Press-Control $window 'Subtitle for video-fixture.avi' ([Windows.Automation.ControlType]::ComboBox) -Pointer
            foreach ($key in @(0x24,0x28,0x0d)) {
                [VlcGuiWindow]::PostMessage($mainWindowHandle,0x0100,[IntPtr]$key,[IntPtr]::Zero) | Out-Null
                [VlcGuiWindow]::PostMessage($mainWindowHandle,0x0101,[IntPtr]$key,[IntPtr]::Zero) | Out-Null
                Start-Sleep -Milliseconds 100
            }
            Press-Control $window 'Save Selected Subtitle Matches'
            Wait-VisibleControl $window '2 associations saved; 2 queued items updated for their next playback; 0 failed.' ([Windows.Automation.ControlType]::Text) | Out-Null
            Save-WindowScreenshot $window 'qt-subtitle-matches-saved.png'
            $afterMatch = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            if ($afterMatch.state -ne $beforeMatch.state -or $afterMatch.currentplid -ne $beforeMatch.currentplid -or
                [Math]::Abs($afterMatch.position-$beforeMatch.position) -gt 0.01) { throw 'Bulk subtitle save changed current playback' }
            Press-Control $window 'Close Subtitle Matching'
            Press-Control $window 'Next' -Pointer
            $matchedMedia = Wait-PlaybackState 'playing' $beforeMatch.currentplid $true
            $trackDeadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                $matchedMedia = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
                $subtitleTracks = @($matchedMedia.information.category.PSObject.Properties | Where-Object { $_.Value.Type -eq 'Subtitle' })
                if ($subtitleTracks.Count) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $trackDeadline)
            if (!$subtitleTracks.Count) { throw 'The next queued media did not load its matched subtitle through VLC' }
            Press-Control $window 'Previous' -Pointer
            Wait-PlaybackState 'playing' $beforeMatch.currentplid | Out-Null
            Wait-VideoDecoderReady $beforeMatch.currentplid
            Press-Control $window 'Play/Pause' -Pointer
            Wait-PlaybackState 'paused' | Out-Null
            Record-Check 'bulk subtitle review, library associations and native queued subtitle loading' @{saved=2; ambiguous_reviewed=$true; subtitle_tracks=$subtitleTracks.Count}

            # Prepare actual player timing, save through the UI, then verify
            # automatic application and restoration through native media changes.
            foreach ($command in @('rate&val=1.25','audiodelay&val=0.1','subdelay&val=0.25')) {
                Invoke-RestMethod ($statusUrl+'?command='+$command) -DisableKeepAlive -Headers $headers -TimeoutSec 3 | Out-Null
            }
            Wait-Timing 1.25 0.1 0.25 | Out-Null
            Press-Control $window 'Extended settings'
            Press-Control $window 'Playback' ([Windows.Automation.ControlType]::TabItem)
            $presetField = Scroll-ToControl 'Folder Timing Preset Name' ([Windows.Automation.ControlType]::Edit)
            $presetField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('')
            Press-Control $window 'Save Folder Timing Preset'
            Wait-VisibleControl $window 'Enter a preset name of 1 to 80 characters while playing a local file.' ([Windows.Automation.ControlType]::Text) | Out-Null
            Wait-Timing 1.25 0.1 0.25 | Out-Null
            Record-Check 'empty timing preset name rejected without changing playback timing' @{rate=1.25}
            $presetField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('CI temporary show')
            Press-Control $window 'Save Folder Timing Preset'
            Wait-VisibleControl $window 'Timing preset applied: CI temporary show' ([Windows.Automation.ControlType]::Text) | Out-Null
            Save-WindowScreenshot $window 'qt-folder-preset-saved.png'
            Press-Control $window 'Next' -Pointer
            Wait-PlaybackState 'playing' $beforeMatch.currentplid $true | Out-Null
            Wait-Timing 1 0 0 | Out-Null
            Press-Control $window 'Previous' -Pointer
            Wait-PlaybackState 'playing' $beforeMatch.currentplid | Out-Null
            Wait-Timing 1.25 0.1 0.25 | Out-Null
            Wait-VideoDecoderReady $beforeMatch.currentplid
            Press-Control $window 'Play/Pause' -Pointer
            Wait-PlaybackState 'paused' | Out-Null
            Record-Check 'folder timing save, automatic application and outside-folder restoration' @{rate=1.25; audio_delay=0.1; subtitle_delay=0.25}
        }

        Press-Control $window 'Extended settings'
        Press-Control $window 'Playback' ([Windows.Automation.ControlType]::TabItem)
        $minutes = Scroll-ToControl 'Sleep Timer Minutes' ([Windows.Automation.ControlType]::Edit)
        if (!$minutes) { throw 'No editable sleep timer duration' }
        $minutes.SetFocus()
        $minutes.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('1')
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0100, [IntPtr]0x0d, [IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle, 0x0101, [IntPtr]0x0d, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 200
        Press-Control $window 'Sleep Timer'
        $beforeTimer = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        if ($beforeTimer.state -eq 'paused') { Press-Control $window 'Play/Pause' -Pointer }
        Wait-PlaybackState 'playing' | Out-Null
        $timerWatch = [Diagnostics.Stopwatch]::StartNew()
        do {
            try {
                $timerStatus = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            } catch {
                Save-ShutdownDiagnostics
                throw
            }
            if ($timerStatus.state -eq 'stopped') { break }
            Start-Sleep -Milliseconds 250
        } while ($timerWatch.Elapsed.TotalSeconds -lt 75)
        if ($timerStatus.state -ne 'stopped' -or $timerWatch.Elapsed.TotalSeconds -lt 55) { throw 'The one-minute sleep timer did not stop playback at its deadline' }
        Save-WindowScreenshot $window 'qt-sleep-timer-expired.png'
        Record-Check 'one-minute sleep timer expiry' @{elapsed_seconds=$timerWatch.Elapsed.TotalSeconds; state=$timerStatus.state}
    }
    Save-WindowScreenshot $window 'qt-window.png'
    $proc.Refresh()
    $peakWorkingSetBytes = $proc.PeakWorkingSet64
    Write-Host 'Playback checks complete; requesting native shutdown'
    Close-NativeWindow $window
    if (!$proc.WaitForExit(60000)) { Save-ShutdownDiagnostics; throw 'Native Qt window did not shut down cleanly within 60 seconds' }
    if ($proc.ExitCode -ne 0) { throw "Native Qt shutdown returned $($proc.ExitCode)" }
    if ($TestLibraryTools -and $VideoFixture) {
        $proc = Start-Process $exe.FullName -ArgumentList $arguments -WorkingDirectory $exe.DirectoryName -PassThru `
            -RedirectStandardOutput (Join-Path $OutputDirectory 'restart-stdout.txt') `
            -RedirectStandardError (Join-Path $OutputDirectory 'restart-stderr.txt')
        $restartDeadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            $proc.Refresh()
            if ($proc.HasExited) { throw 'VLC exited during the folder-preset restart' }
            if ($proc.MainWindowHandle -ne 0) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $restartDeadline)
        if ($proc.MainWindowHandle -eq 0) { throw 'No native Qt window after folder-preset restart' }
        $mainWindowHandle = $proc.MainWindowHandle
        $window = [Windows.Automation.AutomationElement]::FromHandle($mainWindowHandle)
        [VlcGuiWindow]::SetWindowPos($mainWindowHandle,[IntPtr]::Zero,20,20,$wideWidth,$wideHeight,0x14) | Out-Null
        [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
        Wait-VisibleControl $window 'Main interface' | Out-Null
        Wait-PlaybackState 'playing' | Out-Null
        Wait-Timing 1.25 0.1 0.25 | Out-Null
        Press-Control $window 'Extended settings'
        Press-Control $window 'Playback' ([Windows.Automation.ControlType]::TabItem)
        Scroll-ToControl 'Folder Timing Preset Name' ([Windows.Automation.ControlType]::Edit) | Out-Null
        Wait-VisibleControl $window 'Timing preset applied: CI temporary show' ([Windows.Automation.ControlType]::Text) | Out-Null
        Save-WindowScreenshot $window 'qt-folder-preset-restored-after-restart.png'
        Press-Control $window 'Remove Folder Timing Preset'
        Wait-Timing 1 0 0 | Out-Null
        Save-WindowScreenshot $window 'qt-folder-preset-removed.png'
        # Ctrl+1 creates a fresh input through MediaLib's recent-item lookup.
        # Require an associated file outside the media directory in the new
        # native input log, so automatic same-folder discovery cannot pass this.
        $libraryBefore = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
        $restartLog = Join-Path $OutputDirectory 'restart-stderr.txt'
        $logLinesBefore = @(Get-Content $restartLog).Count
        [VlcGuiWindow]::PostMessage($mainWindowHandle,0x0100,[IntPtr]0x1b,[IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::PostMessage($mainWindowHandle,0x0101,[IntPtr]0x1b,[IntPtr]::Zero) | Out-Null
        [VlcGuiWindow]::SetForegroundWindow($mainWindowHandle) | Out-Null
        [VlcGuiWindow]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x31,0,0,[UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x31,0,2,[UIntPtr]::Zero)
        [VlcGuiWindow]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
        $libraryMedia = Wait-PlaybackState 'playing' $libraryBefore.currentplid $true
        $libraryDeadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $associatedLoad = @(Get-Content $restartLog | Select-Object -Skip $logLinesBefore |
                Select-String -Pattern 'loading spu slave:.*matching-subtitles/')
            $libraryMedia = Invoke-RestMethod $statusUrl -DisableKeepAlive -Headers $headers -TimeoutSec 3
            $restoredTracks = @($libraryMedia.information.category.PSObject.Properties | Where-Object { $_.Value.Type -eq 'Subtitle' })
            if ($associatedLoad.Count -and $restoredTracks.Count -and $libraryMedia.stats.decodedvideo -gt 0) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $libraryDeadline)
        if (!$associatedLoad.Count -or !$restoredTracks.Count -or $libraryMedia.stats.decodedvideo -le 0) {
            throw 'Fresh library input did not decode video and restore its persisted external subtitle association'
        }
        Save-WindowScreenshot $window 'qt-subtitle-association-library-reopen.png'
        Record-Check 'persisted subtitle association restored through fresh library input after restart' @{new_item=$libraryMedia.currentplid; native_load_log=$associatedLoad[0].Line}
        Close-NativeWindow $window
        if (!$proc.WaitForExit(60000)) { Save-ShutdownDiagnostics; throw 'Restarted folder-preset process did not exit normally' }
        if ($proc.ExitCode -ne 0) { throw "Folder-preset restart returned $($proc.ExitCode)" }
        Record-Check 'folder timing persisted through native restart and removal restored defaults' @{rate=1.25; restored_rate=1; clean_exits=2}
    }
    $qmlErrors = Select-String -Path (Join-Path $OutputDirectory '*stderr.txt') -Pattern 'ReferenceError:|TypeError:|is not a type|failed to load component'
    if ($qmlErrors) { throw ("Runtime QML errors: " + ($qmlErrors | Out-String)) }
    if ($featureErrors.Count) { throw ($featureErrors -join "; ") }
    @{
        startup_seconds = $startupSeconds
        peak_working_set_bytes = $peakWorkingSetBytes
        native_shutdown = 'passed'
        application_profile = $applicationProfileCheck
        volume_control = $volumeCheck
        settings_categories_requested = $settingsChecks
        settings_categories_verified = @($settingsChecks | Where-Object { $_ -notin $missingAccessibleHeadings })
        missing_accessible_settings_headings = $missingAccessibleHeadings
        seek_preview = $seekPreviewCheck
        playback_tools_controls = $playbackToolsChecks
        startup = 'passed'; media_fixture = $fixture; decoded_media = 'passed'; video_checks = $videoChecks
        native_play_pause_accessibility = 'passed'; native_resume_accessibility = 'passed'
        audio_output = 'dummy (hardware output not tested)'; resize_play_pause = 'passed'; native_seek = 'passed'; native_playlist_next_previous = 'passed'; theme = $(if ($VideoFixture) { 'Dark restored by application profile test' } else { 'Dark seeded; profile test not run' }); desktop = "${desktopWidth}x${desktopHeight}"; sizes = @("${wideWidth}x${wideHeight}", '700x600', "${wideWidth}x${wideHeight}")
        initial = $initial.state; paused = $paused.state; resumed = $resumed.state
        untested = @('hardware audio output', 'volume and mute with a supported output', 'tracks',
            'settings persistence', 'DPI scaling', 'visual fidelity', 'performance') +
            $(if ($VideoFixture) { @('volume on an audio/video file') } else { @() }) +
            $(if (!$DeepFeatures) { @('timer expiry', 'subtitle cue seeking', 'bookmarks', 'customization') } else { @() })
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
    @{ status = 'failed'; error = $failure.Exception.Message; feature_errors = $featureErrors } | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'results.json')
    throw $failure
} finally {
    $proc.Refresh()
    if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
