<#
.SYNOPSIS
    Tests whether Change Tracking works in the Azure SQL Database container lab.

.DESCRIPTION
    Creates the scratch database [ct_test_scratch], tries to enable Change
    Tracking on the database and a table, records one change, reads it back
    with CHANGETABLE, and drops the database.  Each step prints PASS or FAIL
    with the error number and message.

    Microsoft's container FAQ lists Change Tracking as not included, while the
    Azure Functions SQL trigger, used by some event-driven samples, depends on
    it.  This test shows what the engine actually does.

.PARAMETER Container
    The lab container name.

.PARAMETER Distro
    WSL distribution that runs Docker.

.PARAMETER KeepDatabase
    Leave [ct_test_scratch] in place after the test.

.EXAMPLE
    .\Test-ChangeTracking.ps1
#>
[CmdletBinding()]
param(
    [string] $Container = 'azsqldb-lab',
    [string] $Distro = 'Debian',
    [switch] $KeepDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $PSScriptRoot '..\..\scripts'
$invoke = Join-Path $scripts 'Invoke-AzureSqlDbLabSql.ps1'

$drop = Join-Path $PSScriptRoot '03-drop-database.sql'

# Start from a clean scratch database so the test can be rerun.
& $invoke -Container $Container -Distro $Distro -Database 'master' -Path $drop
& $invoke -Container $Container -Distro $Distro -Database 'master' -Path (Join-Path $PSScriptRoot '01-create-database.sql')
try {
    & $invoke -Container $Container -Distro $Distro -Database 'ct_test_scratch' -Path (Join-Path $PSScriptRoot '02-test-change-tracking.sql')
}
finally {
    if (-not $KeepDatabase) {
        & $invoke -Container $Container -Distro $Distro -Database 'master' -Path $drop
    }
}
