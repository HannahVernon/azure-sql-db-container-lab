<#
.SYNOPSIS
    Tests the Azure Functions SQL trigger against the Azure SQL Database container lab.

.DESCRIPTION
    Microsoft's container FAQ lists Change Tracking as not included, while the
    Azure Functions SQL trigger, which depends on it, is documented as the local
    event-driven option.  This script runs a real function against the lab and
    reports PASS or FAIL.

    Steps:
      1. Copies the function project to a private temporary folder.
      2. Creates the scratch database [ct_func_scratch] and a throwaway login
         [ct_func_test] with a random password generated in memory.  The login
         is db_owner of the scratch database only, because the trigger creates
         its own az_func schema and lease tables.
      3. Writes the connection string, built with SqlConnectionStringBuilder, to
         local.settings.json in the temporary folder.  The Functions host reads
         connection settings only from there or from environment variables, so
         this throwaway password is the one secret this lab writes to a file.
      4. Starts Azurite (pinned by digest) for the host's storage, and the
         Functions host in the background.
      5. Inserts, updates and deletes rows, then checks what the function saw.
      6. Always stops the host and Azurite, drops the login and the database,
         and deletes the temporary folder, including local.settings.json.

    Requires Azure Functions Core Tools 4.x, the .NET 8 SDK, and the lab running
    (Start-AzureSqlDbLab.ps1).  The NuGet packages are pinned in the project, and
    NuGetAudit fails the build on any known-vulnerable package.

.PARAMETER Container
    The lab container name.

.PARAMETER Distro
    WSL distribution that runs Docker.

.PARAMETER Port
    Host port of the lab on 127.0.0.1.

.PARAMETER FuncPath
    Path to func.exe.  Defaults to func on PATH, then the Core Tools install folder.

.PARAMETER AzuriteImage
    Azurite image, pinned by digest.

.PARAMETER TimeoutSeconds
    How long to wait for the host to start its trigger listener.

.PARAMETER KeepWorkDir
    Keep the temporary folder for troubleshooting.  It holds local.settings.json
    with the throwaway login's password; the login itself is still dropped.

.EXAMPLE
    .\Test-FunctionsTrigger.ps1
#>
[CmdletBinding()]
param(
    [string] $Container = 'azsqldb-lab',
    [string] $Distro = 'Debian',
    [ValidateRange(1024, 65535)] [int] $Port = 14331,
    [string] $FuncPath,
    [string] $AzuriteImage = 'mcr.microsoft.com/azure-storage/azurite@sha256:c26024d62bf4a5b88a40968afd217234c00e1fc9a4790dc6105d1ca7979f6eec',
    [ValidateRange(30, 900)] [int] $TimeoutSeconds = 180,
    [switch] $KeepWorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\scripts\AzureSqlDbLab.psm1') -Force
Assert-LabName -Name $Container -What 'Container'

if (-not $FuncPath) {
    $cmd = Get-Command func -ErrorAction SilentlyContinue
    if ($cmd) { $FuncPath = $cmd.Source }
    else { $FuncPath = Join-Path $env:ProgramFiles 'Microsoft\Azure Functions Core Tools\func.exe' }
}
if (-not (Test-Path -LiteralPath $FuncPath)) { throw "Azure Functions Core Tools not found at '$FuncPath'.  Install it, or pass -FuncPath." }

function Stop-ProcessTree {
    param([int] $RootId)
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$RootId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-ProcessTree -RootId ([int]$child.ProcessId) }
    Stop-Process -Id $RootId -Force -ErrorAction SilentlyContinue
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('azsqldb-lab-functest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'project\*') -Destination $work -Recurse

$azuriteName = "$Container-azurite"
$funcProc = $null
$lines = @()
$listenerStarted = $false

try {
    # A throwaway password that meets the policy, generated in memory.
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%*+-_.'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    do {
        $bytes = New-Object byte[] 28
        $rng.GetBytes($bytes)
        $testPassword = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    } until ($testPassword -cmatch '[A-Z]' -and $testPassword -cmatch '[a-z]' -and $testPassword -match '[0-9]' -and $testPassword -match '[^A-Za-z0-9]')

    $createSql = @(
        "IF NOT EXISTS (SELECT 1 FROM [sys].[databases] AS [d] WHERE [d].[name] = N'ct_func_scratch')"
        'BEGIN'
        '    CREATE DATABASE [ct_func_scratch];'
        'END;'
        "IF NOT EXISTS (SELECT 1 FROM [sys].[sql_logins] AS [l] WHERE [l].[name] = N'ct_func_test')"
        'BEGIN'
        "    CREATE LOGIN [ct_func_test] WITH PASSWORD = N'$testPassword';"
        'END;'
    ) -join "`n"
    Invoke-LabSqlText -Distro $Distro -Container $Container -Database 'master' -Sql $createSql | Out-Null
    Invoke-LabSqlText -Distro $Distro -Container $Container -Database 'ct_func_scratch' -Sql ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'setup-scratch.sql'))) | Out-Null

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = "127.0.0.1,$Port"
    $builder['Initial Catalog'] = 'ct_func_scratch'
    $builder['User ID'] = 'ct_func_test'
    $builder['Password'] = $testPassword
    $builder['Encrypt'] = $true
    # Local lab only: skips certificate validation, which allows a man-in-the-middle attack.
    $builder['TrustServerCertificate'] = $true
    $settings = [ordered]@{
        IsEncrypted = $false
        Values      = [ordered]@{
            AzureWebJobsStorage      = 'UseDevelopmentStorage=true'
            FUNCTIONS_WORKER_RUNTIME = 'dotnet-isolated'
            SqlConnectionString      = $builder.ConnectionString
        }
    }
    [IO.File]::WriteAllText((Join-Path $work 'local.settings.json'), ($settings | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding ($false)))
    $testPassword = $null
    $builder = $null

    Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'rm', '-f', $azuriteName) -AllowFailure | Out-Null
    Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'run', '-d', '--name', $azuriteName, '-p', '127.0.0.1:10000:10000', '-p', '127.0.0.1:10001:10001', '-p', '127.0.0.1:10002:10002', $AzuriteImage) | Out-Null

    $outLog = Join-Path $work 'func.out.log'
    $errLog = Join-Path $work 'func.err.log'
    $funcProc = Start-Process -FilePath $FuncPath -ArgumentList 'start' -WorkingDirectory $work -RedirectStandardOutput $outLog -RedirectStandardError $errLog -NoNewWindow -PassThru

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not $funcProc.HasExited) {
        Start-Sleep -Seconds 2
        if ((Test-Path -LiteralPath $outLog) -and ((Get-Content -LiteralPath $outLog -Raw) -match 'Started SQL trigger listener')) {
            $listenerStarted = $true
            break
        }
    }
    if (-not $listenerStarted) {
        $tail = if (Test-Path -LiteralPath $outLog) { (Get-Content -LiteralPath $outLog -Tail 15) -join "`n" } else { '(no output)' }
        throw "The SQL trigger listener did not start within $TimeoutSeconds seconds.`n$tail"
    }

    Invoke-LabSqlText -Distro $Distro -Container $Container -Database 'ct_func_scratch' -Sql ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'changes.sql'))) | Out-Null

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $log = Get-ChildItem -Path (Join-Path $work 'bin') -Recurse -Filter 'changes.log' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($log) {
            $lines = @(Get-Content -LiteralPath $log.FullName)
            if ($lines.Count -ge 2) { break }
        }
    }
}
finally {
    if ($funcProc -and -not $funcProc.HasExited) { Stop-ProcessTree -RootId $funcProc.Id }
    Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'rm', '-f', $azuriteName) -AllowFailure | Out-Null
    try {
        Invoke-LabSqlText -Distro $Distro -Container $Container -Database 'master' -Sql ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'cleanup.sql'))) | Out-Null
    }
    catch {
        Write-Warning "Cleanup of [ct_func_scratch] and [ct_func_test] failed; run cleanup.sql on a master connection.  $($_.Exception.Message)"
    }
    if ($KeepWorkDir) {
        Write-Warning "Kept $work.  Its local.settings.json holds the dropped test login's password; delete the folder when you are done."
    }
    else {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Change Tracking reports net changes: row 2's insert and update arrive as one
# Insert with the updated title, and row 1's insert and delete as one Delete.
$expected = @('Insert Id=2 Title=second, updated', 'Delete Id=1 Title=')
$missing = @($expected | Where-Object { $lines -notcontains $_ })

[pscustomobject]@{
    Result          = $(if ($listenerStarted -and $missing.Count -eq 0) { 'PASS' } else { 'FAIL' })
    ListenerStarted = $listenerStarted
    Changes         = $lines
    Missing         = $missing
}
