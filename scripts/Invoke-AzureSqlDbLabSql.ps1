<#
.SYNOPSIS
    Runs a T-SQL script or query in the Azure SQL Database container lab.

.DESCRIPTION
    Sends the T-SQL to the sqlcmd bundled in the container over standard input.
    The sa password comes from the Compose secret mounted in the container, so
    nothing secret crosses the command line.  Scripting variables are disabled
    (-x) and sqlcmd stops on the first error (-b).

    Azure SQL Database does not support USE.  Pick the database with -Database;
    create databases on a master connection.

.PARAMETER Path
    A .sql file to run.  GO separates batches.

.PARAMETER Query
    T-SQL text to run instead of a file.

.PARAMETER Database
    The database to connect to.

.PARAMETER Container
    The lab container name.

.PARAMETER Distro
    WSL distribution that runs Docker.

.EXAMPLE
    .\Invoke-AzureSqlDbLabSql.ps1 -Path ..\sql\build-check.sql

.EXAMPLE
    .\Invoke-AzureSqlDbLabSql.ps1 -Database appdb -Query 'SELECT DB_NAME();'
#>
[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory, ParameterSetName = 'File')] [string] $Path,
    [Parameter(Mandatory, ParameterSetName = 'Query')] [string] $Query,
    [string] $Database = 'master',
    [string] $Container = 'azsqldb-lab',
    [string] $Distro = 'Debian'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AzureSqlDbLab.psm1') -Force

$sql = if ($PSCmdlet.ParameterSetName -eq 'File') { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath) } else { $Query }
Invoke-LabSqlText -Distro $Distro -Container $Container -Database $Database -Sql $sql
