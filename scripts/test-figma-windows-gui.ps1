param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
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

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$password = [Guid]::NewGuid().ToString('N')
$headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + $password))}
$statusUrl = "http://127.0.0.1:$port/requests/status.json"
$config = Join-Path $OutputDirectory 'vlcrc'
$arguments = @('--intf=qt', '--no-one-instance', '--no-qt-privacy-ask',
    '--no-qt-updates-notif', '--no-qt-error-dialogs', '--aout=dummy', '--loop',
    '--extraintf=http', '--http-host=127.0.0.1', "--http-port=$port", "--http-password=$password",
    "--config=`"$config`"", "`"$fixture`"")
$proc = Start-Process $exe.FullName -ArgumentList $arguments -WorkingDirectory $exe.DirectoryName -PassThru `
    -RedirectStandardOutput (Join-Path $OutputDirectory 'stdout.txt') `
    -RedirectStandardError (Join-Path $OutputDirectory 'stderr.txt')

function Wait-PlaybackState([string]$Expected) {
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $last = 'No HTTP response'
    while ([DateTime]::UtcNow -lt $deadline) {
        $proc.Refresh()
        if ($proc.HasExited) { throw "VLC exited unexpectedly: $($proc.ExitCode)" }
        try {
            $status = Invoke-RestMethod $statusUrl -Headers $headers -TimeoutSec 3
            $last = "state=$($status.state), length=$($status.length)"
            if ($status.state -eq $Expected -and $status.length -gt 0) { return $status }
        } catch { $last = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw "Expected $Expected; last observation: $last"
}

function Press-PlayPause($Window) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Play/Pause')
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
    throw 'No visible, enabled, actionable native Play/Pause button'
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
    Press-PlayPause $window
    $paused = Wait-PlaybackState 'paused'
    Press-PlayPause $window
    $resumed = Wait-PlaybackState 'playing'

    $bounds = $window.Current.BoundingRectangle
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'Qt window has empty bounds' }
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $OutputDirectory 'qt-window.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    @{
        startup = 'passed'; local_wav_decode = 'passed'
        native_play_pause_accessibility = 'passed'; native_resume_accessibility = 'passed'
        audio_output = 'dummy (hardware output not tested)'
        initial = $initial.state; paused = $paused.state; resumed = $resumed.state
        untested = @('video output', 'fullscreen', 'seek', 'volume', 'playlists', 'tracks',
            'settings persistence', 'DPI scaling', 'visual fidelity', 'performance')
    } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'results.json')
} finally {
    $proc.Refresh()
    if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
