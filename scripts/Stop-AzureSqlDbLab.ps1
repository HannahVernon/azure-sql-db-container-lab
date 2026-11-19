<#
.SYNOPSIS
    Stops the Azure SQL Database container lab.

.DESCRIPTION
    Stops the Compose project with a 60-second grace period, so the engine can
    shut down cleanly instead of being killed (exit code 137).  The data volume
    is kept unless -RemoveVolume is given.  Ends the keep-alive process that
    Start-AzureSqlDbLab.ps1 -KeepAlive started.

.PARAMETER Distro
    WSL distribution that runs Docker.

.PARAMETER Project
    Compose project name.

.PARAMETER Remove
    Remove the container (docker compose down) after stopping it.

.PARAMETER RemoveVolume
    Also delete the named data volume, and every database in it.

.EXAMPLE
    .\Stop-AzureSqlDbLab.ps1

.EXAMPLE
    .\Stop-AzureSqlDbLab.ps1 -Remove -RemoveVolume
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $Distro = 'Debian',
    [string] $Project = 'azsqldb-lab',
    [switch] $Remove,
    [switch] $RemoveVolume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AzureSqlDbLab.psm1') -Force
Assert-LabName -Name $Project -What 'Project'

if ($PSCmdlet.ShouldProcess($Project, 'docker compose stop')) {
    Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'compose', '-p', $Project, 'stop', '-t', '60')
}

if ($Remove -or $RemoveVolume) {
    $downArgs = @('docker', 'compose', '-p', $Project, 'down')
    $action = 'docker compose down'
    if ($RemoveVolume) {
        $downArgs += '--volumes'
        $action = 'docker compose down --volumes (deletes every database in the volume)'
    }
    if ($PSCmdlet.ShouldProcess($Project, $action)) {
        Invoke-LabWsl -Distro $Distro -Arguments $downArgs
    }
}

$pidFile = Join-Path ([IO.Path]::GetTempPath()) "azsqldb-lab-keepalive-$Project.pid"
if (Test-Path -LiteralPath $pidFile) {
    $keepPid = [int](Get-Content -LiteralPath $pidFile -Raw)
    $proc = Get-Process -Id $keepPid -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq 'wsl' -and $PSCmdlet.ShouldProcess("wsl.exe process $keepPid", 'Stop keep-alive')) {
        Stop-Process -Id $keepPid
    }
    Remove-Item -LiteralPath $pidFile
}
