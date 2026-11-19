Set-StrictMode -Version Latest

<#
    Shared helpers for the Azure SQL Database container lab scripts.

    Windows PowerShell 5.1 and PowerShell 7 are both supported.  Docker runs
    inside a WSL distribution; these helpers call it through wsl.exe.
#>

$credManSource = @(
    'using System;'
    'using System.Runtime.InteropServices;'
    'namespace AzureSqlDbLab'
    '{'
    '    public static class CredMan'
    '    {'
    '        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]'
    '        public struct CREDENTIAL'
    '        {'
    '            public uint Flags;'
    '            public uint Type;'
    '            public IntPtr TargetName;'
    '            public IntPtr Comment;'
    '            public long LastWritten;'
    '            public uint CredentialBlobSize;'
    '            public IntPtr CredentialBlob;'
    '            public uint Persist;'
    '            public uint AttributeCount;'
    '            public IntPtr Attributes;'
    '            public IntPtr TargetAlias;'
    '            public IntPtr UserName;'
    '        }'
    '        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]'
    '        public static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);'
    '        [DllImport("advapi32.dll")]'
    '        public static extern void CredFree(IntPtr credential);'
    '    }'
    '}'
) -join "`n"

if (-not ('AzureSqlDbLab.CredMan' -as [type])) {
    Add-Type -TypeDefinition $credManSource
}

function Get-LabCredential {
    <#
    .SYNOPSIS
        Reads a generic credential from Windows Credential Manager as a PSCredential.
    .DESCRIPTION
        The password stays in a read-only SecureString.  Create the credential with
        "cmdkey /generic:<target> /user:sa /pass", which prompts for the password
        instead of taking it on the command line.
    .PARAMETER Target
        The generic credential's target name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Target
    )

    $ptr = [IntPtr]::Zero
    # Type 1 is CRED_TYPE_GENERIC.
    if (-not [AzureSqlDbLab.CredMan]::CredRead($Target, 1, 0, [ref]$ptr)) {
        throw "No generic credential named '$Target' in Credential Manager.  Create one with: cmdkey /generic:$Target /user:sa /pass"
    }
    try {
        $c = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][AzureSqlDbLab.CredMan+CREDENTIAL])
        $secure = New-Object Security.SecureString
        for ($i = 0; $i -lt $c.CredentialBlobSize; $i += 2) {
            $secure.AppendChar([char][Runtime.InteropServices.Marshal]::ReadInt16($c.CredentialBlob, $i))
        }
        $secure.MakeReadOnly()
        $user = [Runtime.InteropServices.Marshal]::PtrToStringUni($c.UserName)
        New-Object Management.Automation.PSCredential ($user, $secure)
    }
    finally {
        [AzureSqlDbLab.CredMan]::CredFree($ptr)
    }
}

function Test-LabPasswordPolicy {
    <#
    .SYNOPSIS
        Checks a password against the container's sa password policy.
    .DESCRIPTION
        At least 8 characters, with at least three of: upper case, lower case,
        digits and symbols.  The engine does not start with a weaker password on a
        new volume.
    .PARAMETER Credential
        The credential whose password to check.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [Management.Automation.PSCredential] $Credential
    )

    $plain = $Credential.GetNetworkCredential().Password
    try {
        $classes = 0
        if ($plain -cmatch '[A-Z]') { $classes++ }
        if ($plain -cmatch '[a-z]') { $classes++ }
        if ($plain -match '[0-9]') { $classes++ }
        if ($plain -match '[^A-Za-z0-9]') { $classes++ }
        ($plain.Length -ge 8) -and ($classes -ge 3) -and ($plain -notmatch "[`r`n]")
    }
    finally {
        $plain = $null
    }
}

function Assert-LabName {
    <#
    .SYNOPSIS
        Throws unless a name is a plain identifier that is safe to pass to shells and T-SQL.
    .PARAMETER Name
        The value to check.
    .PARAMETER What
        A label for the error message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $What
    )

    if ($Name -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$') {
        throw "$What '$Name' must be 1 to 128 characters of letters, digits, underscore, period or hyphen, and must not start with a period or hyphen."
    }
}

function Invoke-LabWsl {
    <#
    .SYNOPSIS
        Runs a command in a WSL distribution and throws on a non-zero exit code.
    .PARAMETER Distro
        The WSL distribution name.
    .PARAMETER Arguments
        The command and its arguments, passed after "--".
    .PARAMETER WorkingDirectory
        A Linux path to start in.
    .PARAMETER InputText
        Text to send on standard input.  UTF-8 without a byte order mark.
    .PARAMETER AllowFailure
        Return the exit code instead of throwing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Distro,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $WorkingDirectory,
        [string] $InputText,
        [switch] $AllowFailure
    )

    $wslArgs = @('-d', $Distro)
    if ($WorkingDirectory) { $wslArgs += @('--cd', $WorkingDirectory) }
    # -e runs the command directly.  "--" would hand the command line to the
    # distribution's default shell, which would expand $(...) on the WSL side.
    $wslArgs += '-e'
    $wslArgs += $Arguments

    $savedEncoding = $OutputEncoding
    $savedPreference = $ErrorActionPreference
    $errFile = [IO.Path]::GetTempFileName()
    $outLines = New-Object Collections.Generic.List[string]
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding ($false)
        # Windows PowerShell 5.1 turns each native stderr line into an error
        # record, which "Stop" makes terminating.  Compose writes progress to
        # stderr, so let it through; the exit code decides success below.
        $ErrorActionPreference = 'Continue'
        # Pass output through as it arrives, and keep a copy so a failure can
        # say why: sqlcmd writes its error messages to standard output.
        if ($PSBoundParameters.ContainsKey('InputText')) {
            $InputText | & wsl.exe @wslArgs 2> $errFile | ForEach-Object { $outLines.Add([string]$_); $_ }
        }
        else {
            & wsl.exe @wslArgs 2> $errFile | ForEach-Object { $outLines.Add([string]$_); $_ }
        }
        $code = $LASTEXITCODE
        $errText = @(Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() } |
            # Windows PowerShell 5.1 wraps the first stderr line in an error
            # record; drop the wrapper so only the tool's own text remains.
            Where-Object { $_ -notmatch '^At .+:\d+ char:\d+$' -and $_ -notmatch '^\s*\+ ' } |
            ForEach-Object { $_ -replace '^wsl\.exe : ', '' })
    }
    finally {
        $OutputEncoding = $savedEncoding
        $ErrorActionPreference = $savedPreference
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }

    # Compose writes its progress to stderr, so pass stderr through as host
    # output rather than treating it as an error.
    foreach ($line in $errText) { Write-Host $line }

    if ($AllowFailure) { return $code }
    if ($code -ne 0) {
        $tail = (@($outLines | Where-Object { $_ -and $_.Trim() }) + $errText | Select-Object -Last 6) -join ' | '
        throw "wsl.exe -d $Distro -e $($Arguments[0]) ... exited with code $code.  $tail"
    }
}

function ConvertTo-LabWslPath {
    <#
    .SYNOPSIS
        Converts a Windows path to the matching path inside a WSL distribution.
    .PARAMETER Path
        The Windows path.
    .PARAMETER Distro
        The WSL distribution name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Distro
    )

    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $converted = & wsl.exe -d $Distro -e wslpath -a ($full -replace '\\', '/')
    if ($LASTEXITCODE -ne 0 -or -not $converted) { throw "wslpath could not convert '$full'." }
    ([string]$converted).Trim()
}

function Invoke-LabSqlText {
    <#
    .SYNOPSIS
        Runs T-SQL inside the lab container with the bundled sqlcmd.
    .DESCRIPTION
        The batch text goes over standard input.  sqlcmd reads the sa password from
        SQLCMDPASSWORD, which is set for the sqlcmd process only, from the Compose
        secret mounted in the container.  Scripting variables are disabled (-x).
    .PARAMETER Distro
        The WSL distribution name.
    .PARAMETER Container
        The container name.
    .PARAMETER Database
        The database to connect to.  Azure SQL Database does not support USE, so
        each script runs on a connection to the database it needs.
    .PARAMETER Sql
        The T-SQL text.  GO separates batches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Distro,
        [Parameter(Mandatory)] [string] $Container,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $Sql
    )

    Assert-LabName -Name $Container -What 'Container'
    Assert-LabName -Name $Database -What 'Database'
    # No double quotes: Windows PowerShell 5.1 does not escape embedded double
    # quotes when it passes arguments to a native program.  The assignment needs
    # no quotes, and the database name has already passed Assert-LabName.
    $inner = 'SQLCMDPASSWORD=$(cat /run/secrets/sa_password) exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -x -W -l 30 -d $1'
    Invoke-LabWsl -Distro $Distro -Arguments @('docker', 'exec', '-i', $Container, 'bash', '-c', $inner, 'sqlcmd', $Database) -InputText $Sql
}

Export-ModuleMember -Function Get-LabCredential, Test-LabPasswordPolicy, Assert-LabName, Invoke-LabWsl, ConvertTo-LabWslPath, Invoke-LabSqlText
