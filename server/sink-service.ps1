# nina — install the remote-sink daemon as a persistent Windows service (Task Scheduler).
# Use on NATIVE Windows only (Python on Windows). WSL installs use sink-service.sh (systemd).
#   powershell -ExecutionPolicy Bypass -File sink-service.ps1 [-Action install|uninstall|restart|status]
param([ValidateSet('install','uninstall','restart','status')][string]$Action = 'install')

$Task   = 'nina-sink'
$Here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sink   = Join-Path $Here 'voice-sink.py'
$Py     = (Get-Command python -ErrorAction SilentlyContinue).Source
$TsExe  = @("$env:ProgramFiles\Tailscale\tailscale.exe","${env:ProgramFiles(x86)}\Tailscale IPN\tailscale.exe") |
          Where-Object { Test-Path $_ } | Select-Object -First 1
$Bind   = if ($env:VOICE_SINK_BIND) { $env:VOICE_SINK_BIND }
          elseif ($TsExe) { (& $TsExe ip -4 | Select-Object -First 1).Trim() } else { '' }

switch ($Action) {
  'install' {
    if (-not $Py)   { throw 'python not found on PATH' }
    if (-not $Bind) { Write-Warning 'no Tailscale IP; sink would bind 127.0.0.1 (not reachable). Set $env:VOICE_SINK_BIND and re-run.' }
    $act = New-ScheduledTaskAction -Execute $Py -Argument "`"$Sink`"" -WorkingDirectory $Here
    $trg = New-ScheduledTaskTrigger -AtLogOn
    # restart on failure + keep running
    $set = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
             -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    $env:VOICE_SINK_BIND = $Bind   # captured into the task's process env at run
    Register-ScheduledTask -TaskName $Task -Action $act -Trigger $trg -Settings $set -Force `
      -Description "nina remote-sink daemon (bind $Bind)" | Out-Null
    Start-ScheduledTask -TaskName $Task
    "installed Scheduled Task -> bind $Bind"
  }
  'uninstall' { Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue; 'removed' }
  'restart'   { Stop-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue; Start-ScheduledTask -TaskName $Task; 'restarted' }
  'status'    { Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue | Get-ScheduledTaskInfo }
}
