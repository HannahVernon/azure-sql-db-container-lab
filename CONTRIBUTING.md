# Contributing

Thanks for considering a contribution.

## What is most welcome

- **Findings from real runs.**  A behaviour of the container that differs from Azure SQL Database or from Microsoft's documentation, with the image digest, the steps, and the evidence.  Add a rerunnable test under `tests/` when you can.
- Fixes to the scripts, especially for runtimes and platforms not yet tested here (Podman, Rancher Desktop, WSL containers, macOS, ARM64).
- Migration rehearsal recipes: deploying with SqlPackage, Flyway, Liquibase or an ORM against the lab.

## Prerequisites

- Git
- Docker Engine 24 or later with the Compose v2 plugin (on Windows, inside a WSL 2 distribution)
- PowerShell 5.1 or 7 for the Windows scripts, bash for the Linux and macOS scripts
- `shellcheck` for changes to `.sh` files

## Branch model

- `main` is the release branch
- `dev` is the integration branch
- Work happens on `feature/xxx` or `fix/xxx` branches taken from `dev`

Open pull requests against `dev`.  `main` receives changes by merging `dev`.

## Before you commit

- Parse every PowerShell file you changed, in both Windows PowerShell 5.1 and PowerShell 7:

  ```powershell
  Get-ChildItem -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
      $tokens = $null; $errors = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
      if ($errors) { "$($_.Name): $($errors[0].Message)" }
  }
  ```

- Run `shellcheck scripts/*.sh compose/*.sh` and fix every finding.
- Start the lab, run `sql/build-check.sql` and `tests/change-tracking/Test-ChangeTracking.ps1`, and stop it again.  Say in the pull request which runtime and platform you used.
- **Never print, trace or log the password.**  Do not run the start scripts with `bash -x` or `Set-PSDebug -Trace`: tracing expands every command, including the one that writes the secret.

## Coding standards

PowerShell:

- Target Windows PowerShell 5.1: no ternaries, null-coalescing or other PowerShell 7 only syntax
- Comment-based help with at least `.SYNOPSIS`, plus `[CmdletBinding()]`
- `Set-StrictMode -Version Latest`
- No here-strings; build multi-line text from arrays
- Variable names that differ by more than case, because PowerShell variable names are case-insensitive
- Call `wsl.exe` with `-e`, not `--`, so the distribution's shell doesn't expand the arguments

Bash:

- `set -euo pipefail`, and shellcheck clean
- LF line endings (enforced by `.gitattributes`)

T-SQL:

- `/* ... */` comments only
- Square-bracketed identifiers, `N''` string literals, semicolon-terminated statements
- No `USE`: name the database on the connection, because Azure SQL Database returns Msg 40508

Documentation:

- One line per paragraph; do not hard-wrap
- No em-dashes or en-dashes.  Use commas, colons, parentheses, or a spaced hyphen ( - )
- Two spaces after a period
- Tables without leading and trailing pipes
- All examples invented.  Never a real host name, database, employer, colleague or password

## Pull requests

One logical change per pull request.  Fill in the template.  If you changed behaviour, say how you verified it, and if you did not verify it, say that instead.
