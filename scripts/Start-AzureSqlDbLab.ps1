<#
.SYNOPSIS
    Starts the Azure SQL Database container lab with Docker Compose in WSL.

.DESCRIPTION
    Reads the sa password from Windows Credential Manager, writes it to a
    short-lived file on the WSL distribution's tmpfs (/dev/shm) through standard
    input, and starts the Compose project with that file as a secret.  The
    password never appears on a command line, in an environment variable of
    the Compose process, in compose.yaml, or in the container's configuration.

    After the engine reports healthy, the script creates the application
    database if it does not exist, then deletes the secret file from tmpfs.
    The file stays mounted in the running container, which the healthcheck and
    Invoke-AzureSqlDbLabSql.ps1 use.  Because the host file is gone, restart
    the lab with this script rather than "docker restart".

    The first start on a new volume sets the sa password from the credential.
    Later starts keep whatever password the volume already has, so change the
    credential and the login together (ALTER LOGIN), or start on a new volume.

.PARAMETER CredentialTarget
    Generic credential in Credential Manager holding the sa password.  Create
    it with: cmdkey /generic:azsqldb-lab-sa /user:sa /pass

.PARAMETER Distro
    WSL distribution that runs Docker Engine and the Compose plugin.

.PARAMETER Port
    Host port on 127.0.0.1 that maps to the container's 1433.

.PARAMETER Database
    Application database to create if it does not exist.  Use an empty string
    to skip.

.PARAMETER Project
    Compose project name.  Use different names to run several labs side by side.

.PARAMETER Container
    Container name.

.PARAMETER Volume
    Named volume for /var/opt/mssql.  The data survives "docker compose down".

.PARAMETER Image
    Container image.  Pin a digest (image@sha256:...) for repeatable test runs.

.PARAMETER TimeoutSeconds
    How long to wait for the engine to report healthy.

.PARAMETER Pull
    Pull the image before starting.

.PARAMETER KeepAlive
    Start a hidden "sleep infinity" in the distribution so WSL does not shut it
    down, and the container with it, when no other WSL process is running.
    Stop-AzureSqlDbLab.ps1 ends it.

.EXAMPLE
    .\Start-AzureSqlDbLab.ps1 -KeepAlive

.EXAMPLE
    .\Start-AzureSqlDbLab.ps1 -Project migtest -Container migtest -Volume migtest-data -Port 14332 -Database sales
#>
[CmdletBinding()]
param(
    [string] $CredentialTarget = 'azsqldb-lab-sa',
    [string] $Distro = 'Debian',
    [ValidateRange(1024, 65535)] [int] $Port = 14331,
    [AllowEmptyString()] [string] $Database = 'appdb',
    [string] $Project = 'azsqldb-lab',
    [string] $Container = 'azsqldb-lab',
    [string] $Volume = 'azsqldb-lab-data',
    [string] $Image = 'mcr.microsoft.com/mssql/azure-sql-db-server:latest',
    [ValidateRange(30, 1800)] [int] $TimeoutSeconds = 300,
    [switch] $Pull,
    [switch] $KeepAlive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AzureSqlDbLab.psm1') -Force

foreach ($pair in @(@($Project, 'Project'), @($Container, 'Container'), @($Volume, 'Volume'))) {
    Assert-LabName -Name $pair[0] -What $pair[1]
}
if ($Database) { Assert-LabName -Name $Database -What 'Database' }
if ($Image -notmatch '^[A-Za-z0-9._/:@-]+$') { throw "Image '$Image' contains unexpected characters." }

$credential = Get-LabCredential -Target $CredentialTarget
if (-not (Test-LabPasswordPolicy -Credential $credential)) {
    throw "The password in '$CredentialTarget' does not meet the sa policy: at least 8 characters, with at least three of upper case, lower case, digits and symbols."
}

$composeDir = ConvertTo-LabWslPath -Path (Join-Path $PSScriptRoot '..\compose') -Distro $Distro

if ($KeepAlive) {
    $pidFile = Join-Path ([IO.Path]::GetTempPath()) "azsqldb-lab-keepalive-$Project.pid"
    $running = $false
    if (Test-Path -LiteralPath $pidFile) {
        $oldPid = [int](Get-Content -LiteralPath $pidFile -Raw)
        $running = [bool](Get-Process -Id $oldPid -ErrorAction SilentlyContinue)
    }
    if (-not $running) {
        $keep = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $Distro, '-e', 'sleep', 'infinity') -WindowStyle Hidden -PassThru
        Set-Content -LiteralPath $pidFile -Value $keep.Id
        Write-Verbose "Keep-alive started, process $($keep.Id)."
    }
}

$composeEnv = @(
    'env'
    "AZSQLDB_PROJECT=$Project"
    "AZSQLDB_CONTAINER=$Container"
    "AZSQLDB_VOLUME=$Volume"
    "AZSQLDB_PORT=$Port"
    "AZSQLDB_IMAGE=$Image"
)

if ($Pull) {
    Invoke-LabWsl -Distro $Distro -WorkingDirectory $composeDir -Arguments ($composeEnv + @('AZSQLDB_SECRET_FILE=/dev/null', 'docker', 'compose', 'pull'))
}

# Write the password to tmpfs through standard input.  The directory is
# private to this user; the file itself must be readable by the container's
# mssql user, which only sees it through the secret mount.
$makeSecret = 'umask 077; d=$(mktemp -d /dev/shm/azsqldb-lab.XXXXXX) && tr -d ''\r\n'' > $d/sa_password && chmod 0444 $d/sa_password && echo $d'
$plain = $credential.GetNetworkCredential().Password
try {
    $secretDir = Invoke-LabWsl -Distro $Distro -Arguments @('bash', '-c', $makeSecret) -InputText $plain
}
finally {
    $plain = $null
}
$secretDir = ([string]($secretDir | Select-Object -Last 1)).Trim()
if ($secretDir -notmatch '^/dev/shm/azsqldb-lab\.[A-Za-z0-9]+$') { throw "Unexpected secret directory '$secretDir'." }

try {
    # --force-recreate: the secret's source file is new on every start, and the
    # previous one was deleted, so the container must be recreated to mount it.
    # The databases live in the named volume and are not affected.
    Invoke-LabWsl -Distro $Distro -WorkingDirectory $composeDir -Arguments ($composeEnv + @("AZSQLDB_SECRET_FILE=$secretDir/sa_password", 'docker', 'compose', 'up', '-d', '--force-recreate', '--wait', '--wait-timeout', "$TimeoutSeconds"))

    if ($Database) {
        # Guard with sys.databases, not DB_ID().  On a master connection DB_ID()
        # returns NULL for an existing user database, so a DB_ID() guard tries
        # CREATE DATABASE again and fails with Msg 1801.
        $createSql = "IF NOT EXISTS (SELECT 1 FROM [sys].[databases] AS [d] WHERE [d].[name] = N'$Database')`nBEGIN`n    CREATE DATABASE [$Database];`nEND;`n"
        Invoke-LabSqlText -Distro $Distro -Container $Container -Database 'master' -Sql $createSql | Out-Null
    }
}
finally {
    Invoke-LabWsl -Distro $Distro -Arguments @('rm', '-rf', '--', $secretDir) -AllowFailure | Out-Null
}

$digest = Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'inspect', '--format', '{{.Image}}', $Container)

[pscustomobject]@{
    Server      = "127.0.0.1,$Port"
    Database    = $(if ($Database) { $Database } else { 'master' })
    Login       = $credential.UserName
    Container   = $Container
    Volume      = $Volume
    ImageId     = ([string]($digest | Select-Object -Last 1)).Trim()
    Certificate = 'Self-signed.  Clients need TrustServerCertificate=True, which skips certificate validation and allows a man-in-the-middle attack.  Acceptable on loopback for a local lab only.'
}
