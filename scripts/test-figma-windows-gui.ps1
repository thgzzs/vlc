param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$VideoFixture
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$exe = @(Get-ChildItem $PackageDirectory -Recurse -Filter vlc.exe -File)
if ($exe.Count -ne 1) { throw "Expected one packaged vlc.exe; found $($exe.Count)" }
$exe = $exe[0]
foreach ($dependency in @('libvlc.dll', 'libvlccore.dll', 'plugins')) {
    if (!(Test-Path (Join-Path $exe.DirectoryName $dependency))) { throw "Missing $dependency" }
}

# Decode a real local WAV without depending on runner audio hardware.
$fixture = Join-Path $OutputDirectory 'audio-fixture.wav'
$pcm = New-Object byte[] (16000 * 2 * 30)
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
public static class VlcGuiWindow {
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
$arguments = @('--intf=qt', '--no-one-instance', '--no-qt-privacy-ask',
    '--no-qt-updates-notif', '--no-qt-error-dialogs', '--aout=dummy', '--loop', '--media-library', '--qt-pin-controls',
    '--extraintf=http', '--http-host=127.0.0.1', "--http-port=$port", "--http-password=$password",
    "--config=`"$config`"", "`"$fixture`"", "`"$nextFixture`"")
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
            $status = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
            $last = "state=$($status.state), length=$($status.length), item=$($status.currentplid)"
            $playlistMatches = $ExpectedItemId -lt 0 -or (($status.currentplid -eq $ExpectedItemId) -ne $DifferentItem)
            if ($status.state -eq $Expected -and $status.length -gt 0 -and $playlistMatches) { return $status }
        } catch { $last = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw "Expected $Expected; last observation: $last"
}

function Press-Control($Window, [string]$Name) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $Name)
    $buttons = $Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)
    foreach ($button in $buttons) {
        if ($button.Current.IsOffscreen -or !$button.Current.IsEnabled) { continue }
        $pattern = $null
        if ($button.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            $pattern.Invoke(); return
        }
        if ($button.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
            $pattern.Toggle(); return
        }
        if ($button.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref]$pattern)) {
            $pattern.DoDefaultAction(); return
        }
    }
    throw "No visible, enabled, actionable native $Name control"
}

try {
    $initial = Wait-PlaybackState 'playing'
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        $proc.Refresh()
        if ($proc.HasExited) { throw 'VLC exited before showing its Qt window' }
        if ($proc.MainWindowHandle -ne 0) { break }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($proc.MainWindowHandle -eq 0) { throw 'No native Qt main window appeared' }
    $window = [Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
    if ($window.Current.IsOffscreen) { throw 'Qt window is offscreen on this runner' }
    if (![VlcGuiWindow]::SetWindowPos($proc.MainWindowHandle, [IntPtr]::Zero, 20, 20, 1440, 900, 0x14)) {
        throw 'Could not resize the Qt window to the wide test layout'
    }
    [VlcGuiWindow]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 1000
    Press-Control $window 'Play/Pause'
    $paused = Wait-PlaybackState 'paused'
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Progress')
    $progress = @($window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object { !$_.Current.IsOffscreen -and $_.Current.IsEnabled }) | Select-Object -First 1
    if (!$progress) { throw 'No visible native progress control' }
    $seekBounds = $progress.Current.BoundingRectangle
    if ($seekBounds.Width -le 100 -or $seekBounds.Height -le 0) { throw 'Progress control has unusable bounds' }
    [VlcGuiWindow]::SetCursorPos([int]($seekBounds.X + $seekBounds.Width * 0.5), [int]($seekBounds.Y + $seekBounds.Height * 0.5)) | Out-Null
    [VlcGuiWindow]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
    [VlcGuiWindow]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    $seekStatus = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
    if ([Math]::Abs($seekStatus.position - 0.5) -gt 0.1) { throw "Native seek failed: position=$($seekStatus.position)" }
    Press-Control $window 'Play/Pause'
    $resumed = Wait-PlaybackState 'playing'

    if (![VlcGuiWindow]::SetWindowPos($proc.MainWindowHandle, [IntPtr]::Zero, 20, 20, 700, 600, 0x14)) {
        throw 'Could not resize the Qt window to the narrow test layout'
    }
    Start-Sleep -Milliseconds 500
    Press-Control $window 'Play/Pause'
    Wait-PlaybackState 'paused' | Out-Null
    if (![VlcGuiWindow]::SetWindowPos($proc.MainWindowHandle, [IntPtr]::Zero, 20, 20, 1440, 900, 0x14)) {
        throw 'Could not restore the wide Qt layout'
    }
    Start-Sleep -Milliseconds 500
    Press-Control $window 'Play/Pause'
    Wait-PlaybackState 'playing' | Out-Null
    Press-Control $window 'Next'
    $nextStatus = Wait-PlaybackState 'playing' $initial.currentplid $true
    if ($nextStatus.currentplid -eq $initial.currentplid) { throw 'Native Next did not select the second playlist item' }
    Press-Control $window 'Previous'
    $previousStatus = Wait-PlaybackState 'playing' $initial.currentplid
    if ($previousStatus.currentplid -ne $initial.currentplid) { throw 'Native Previous did not restore the first playlist item' }
    $videoChecks = 'not run'
    if ($VideoFixture) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $videoStatus = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
            if ($videoStatus.stats.decodedvideo -gt 0) { break }
            Start-Sleep -Milliseconds 500
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($videoStatus.stats.decodedvideo -le 0) { throw 'No video frames decoded' }
        Press-Control $window 'fullscreen'
        Start-Sleep -Milliseconds 1000
        $fullStatus = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
        if ($fullStatus.fullscreen -ne $true) { throw 'Native fullscreen control did not enter fullscreen' }
        # Use the same player backend to leave fullscreen, then verify the native window again.
        Invoke-RestMethod "$statusUrl`?command=fullscreen" -Headers $headers -TimeoutSec 3 | Out-Null
        Start-Sleep -Milliseconds 1000
        $normalStatus = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
        if ($normalStatus.fullscreen -ne $false) { throw 'Could not leave fullscreen' }
        $videoChecks = 'decoded frames and native fullscreen entry passed; backend fullscreen exit passed'
        $videoStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputDirectory 'video-status.json')
    }
    $bounds = $window.Current.BoundingRectangle
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'Qt window has empty bounds' }
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $OutputDirectory 'qt-window.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    @{
        startup = 'passed'; media_fixture = $fixture; decoded_media = 'passed'; video_checks = $videoChecks
        native_play_pause_accessibility = 'passed'; native_resume_accessibility = 'passed'
        audio_output = 'dummy (hardware output not tested)'; resize_play_pause = 'passed'; native_seek = 'passed'; native_playlist_next_previous = 'passed'; theme = 'Night'; sizes = @('1440x900', '700x600', '1440x900')
        initial = $initial.state; paused = $paused.state; resumed = $resumed.state
        untested = @('video output', 'fullscreen', 'volume', 'tracks',
            'settings persistence', 'DPI scaling', 'visual fidelity', 'performance')
    } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'results.json')
} finally {
    $proc.Refresh()
    if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
