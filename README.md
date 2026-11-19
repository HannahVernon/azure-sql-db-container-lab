# Azure SQL Database container lab

Run the Azure SQL Database container on your own machine with Docker Compose, keep the `sa` password out of environment variables and command lines, and test database changes against the Azure SQL Database engine before they reach Azure.

Microsoft released the Azure SQL Database container as a public preview in November 2026.  It runs the Azure SQL Database engine (`EngineEdition` 5), not SQL Server, so features and errors behave the way they do in Azure: `USE` returns Msg 40508, there is no SQL Server Agent, and new databases get Azure's defaults.  That makes it a useful place to rehearse a migration, run a deployment pipeline's tests, or check whether a script written for SQL Server works on Azure SQL Database.

This repository is not affiliated with Microsoft.  For Microsoft's own instructions, see the [getting started guide](https://microsoft.github.io/azure-sql-dev-hub/container/get-started.html) and the [FAQ](https://microsoft.github.io/azure-sql-dev-hub/container/faq.html).

## What is here

Path | Purpose
-----|--------
`compose/compose.yaml` | The Compose project: one engine container, a named data volume, a healthcheck, and the `sa` password as a Compose secret
`compose/sqldb-entrypoint.sh` | A small wrapper that reads the secret and starts the image's normal entrypoint
`scripts/Start-AzureSqlDbLab.ps1` | Windows: reads the password from Credential Manager and starts the lab in a WSL distribution
`scripts/Stop-AzureSqlDbLab.ps1` | Windows: stops the lab, optionally removes the container or the data volume
`scripts/Invoke-AzureSqlDbLabSql.ps1` | Windows: runs a `.sql` file or a query in the lab
`scripts/AzureSqlDbLab.psm1` | Shared helpers for the Windows scripts
`scripts/start-lab.sh`, `stop-lab.sh`, `invoke-lab-sql.sh` | The same three jobs on Linux and macOS
`sql/build-check.sql` | Reports the engine version and confirms `EngineEdition` 5
`tests/change-tracking/` | A rerunnable Change Tracking test (see [Findings](#findings))
`tests/functions-trigger/` | An end-to-end Azure Functions SQL trigger test against the lab (see [Findings](#findings))

## Requirements

- **Windows 11:** a WSL 2 distribution running Docker Engine with the Compose plugin.  Tested with Debian 13, Docker 29.8.2 and Compose 5.6.0, from Windows PowerShell 5.1 and PowerShell 7.  Docker Desktop is not required.
- **Linux or macOS:** Docker 24 or later with Compose v2, and bash.
- At least 2 CPUs and 4 GB of memory for the container runtime, and about 10 GB of disk for the image and a small database.  These are Microsoft's minimums.
- An internet connection for the first image pull.  After that, the container runs offline.

## Quick start on Windows

1. Store the `sa` password in Credential Manager.  `cmdkey` prompts for it when you leave the value off `/pass`, so it never appears on the command line:

   ```powershell
   cmdkey /generic:azsqldb-lab-sa /user:sa /pass
   ```

   The password must have at least 8 characters, with at least three of upper case, lower case, digits and symbols.

2. Start the lab.  `-KeepAlive` keeps the WSL distribution running, because WSL shuts down an idle distribution after a few seconds and the container stops with it:

   ```powershell
   .\scripts\Start-AzureSqlDbLab.ps1 -Pull -KeepAlive
   ```

   The script waits for the engine to report healthy, creates the `appdb` database, and prints the connection details.  Use `-Distro` if your Docker distribution isn't named `Debian`.

3. Run something:

   ```powershell
   .\scripts\Invoke-AzureSqlDbLabSql.ps1 -Path .\sql\build-check.sql
   .\scripts\Invoke-AzureSqlDbLabSql.ps1 -Database appdb -Query 'SELECT DB_NAME();'
   ```

4. Stop it.  The databases stay in the volume until you remove it:

   ```powershell
   .\scripts\Stop-AzureSqlDbLab.ps1
   .\scripts\Stop-AzureSqlDbLab.ps1 -Remove -RemoveVolume   # deletes every database in the lab
   ```

## Quick start on Linux and macOS

```bash
cd scripts
pass show azsqldb-lab/sa | ./start-lab.sh     # or ./start-lab.sh to type it at a prompt that does not echo
./invoke-lab-sql.sh ../sql/build-check.sql
./invoke-lab-sql.sh -d appdb my-migration.sql
./stop-lab.sh
```

Settings come from environment variables, none of them secret: `AZSQLDB_PORT`, `AZSQLDB_PROJECT`, `AZSQLDB_CONTAINER`, `AZSQLDB_VOLUME`, `AZSQLDB_IMAGE`, `AZSQLDB_APPDB` and `AZSQLDB_TIMEOUT`.

## Connecting from an application or a tool

The lab listens on `127.0.0.1,14331` by default, loopback only.  Log in as `sa` with the password from your secret store.

The container uses a self-signed certificate.  Keep encryption on, and set `TrustServerCertificate=True` only for this local lab.  It tells the driver not to validate the server's certificate, which allows a man-in-the-middle attack, so never carry it into a connection string for Azure or any shared server.  Build connection strings with your driver's builder rather than by concatenation:

```powershell
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = '127.0.0.1,14331'
$builder['Initial Catalog'] = 'appdb'
$builder['Encrypt'] = $true
# Local lab only: skips certificate validation, which allows a man-in-the-middle attack.
$builder['TrustServerCertificate'] = $true
```

Azure SQL Database does not support `USE`.  Name the database in the connection, and create databases on a `master` connection.

## How the password is handled

The image reads the `sa` password only from the `MSSQL_SA_PASSWORD` environment variable.  Microsoft's examples pass it with `docker run -e`, which stores it in the container's configuration, where `docker inspect` shows it to anyone who can run Docker.  Docker's own documentation warns that passing passwords as environment variables risks unintentional exposure.

This lab does the following instead:

1. The start script reads the password from Credential Manager on Windows, or from standard input on Linux and macOS.
2. It writes the password through standard input to a file in a private directory on tmpfs (`/dev/shm` or `$XDG_RUNTIME_DIR`), never on a command line.
3. Compose mounts that file into the container as the secret `/run/secrets/sa_password`.
4. `sqldb-entrypoint.sh` reads the secret, exports `MSSQL_SA_PASSWORD` inside the container for the engine's own processes, and runs the image's entrypoint.
5. The healthcheck and the SQL scripts give the password to `sqlcmd` through `SQLCMDPASSWORD`, set for that one process.
6. Once the engine is healthy, the start script deletes the file from tmpfs.  The running container keeps its mount.

The result: the password is not in `compose.yaml`, not in `docker inspect`, not in any host process's command line or environment, and not on disk on the host.

What it does not protect against: anyone who can run `docker exec` on the container can read the secret file or the engine's environment.  That is the same access as root over the container, so treat Docker access as administrator access.

Two consequences to know about:

- **Restart with the start script, not `docker restart`.**  The secret's source file is gone after startup, so Docker can't mount it again.  The start script writes a new file and recreates the container (`--force-recreate`).  Your databases live in the volume and survive the recreation.
- **The password applies only to a new volume.**  On an existing volume the engine keeps the current `sa` password and ignores `MSSQL_SA_PASSWORD`.  To change it, run `ALTER LOGIN [sa] WITH PASSWORD = ...` first, then update the stored credential, or start on a new volume.

## Testing a migration

A typical rehearsal:

1. Start the lab on its own project, volume and port, so it doesn't disturb another lab:

   ```powershell
   .\scripts\Start-AzureSqlDbLab.ps1 -Project migtest -Container migtest -Volume migtest-data -Port 14332 -Database sales
   ```

2. Deploy the schema your way: a DACPAC with SqlPackage, migration scripts, or your ORM's migrations, pointed at `127.0.0.1,14332`.
3. Run your tests and any data checks with `Invoke-AzureSqlDbLabSql.ps1 -Container migtest -Database sales`.
4. Remove it all with `Stop-AzureSqlDbLab.ps1 -Project migtest -Remove -RemoveVolume`.

For repeatable runs, pin the image by digest with `-Image mcr.microsoft.com/mssql/azure-sql-db-server@sha256:...` (or `AZSQLDB_IMAGE`), so a new preview build can't change results between runs.  The container is a development target.  Validate in Azure SQL Database before you deploy to production, especially for the features in Microsoft's list of capabilities the container leaves out.

## Findings

Tested on 2026-11-19 with image digest `sha256:8323f47dad34124f391413c3c3182ca89da5632888df6cfb5326574026599c57` (label `com.microsoft.version` 18.0.256.6210), which reports `Microsoft SQL Azure (RTM) - 12.0.2000.8`, built Nov 17 2026.

**Change Tracking works.**  Microsoft's FAQ lists Change Tracking among the capabilities the container does not include.  On this build, `ALTER DATABASE ... SET CHANGE_TRACKING = ON`, `ALTER TABLE ... ENABLE CHANGE_TRACKING` and `CHANGETABLE(CHANGES ...)` all succeed, and `sys.change_tracking_databases` shows the database.  An earlier private preview build (Oct 25 2026) behaved the same.  Run `tests/change-tracking/Test-ChangeTracking.ps1` to check your build.

**The Azure Functions SQL trigger works against the container.**  This matters because the trigger depends on Change Tracking, and Microsoft documents it as the local event-driven option.  `tests/functions-trigger/Test-FunctionsTrigger.ps1` runs a real .NET 8 isolated function with Azure Functions Core Tools 4.16.0 and `Microsoft.Azure.Functions.Worker.Extensions.Sql` 3.1.549, with Azurite for the host's storage.  The listener starts, creates its `az_func` lease tables, and delivers inserts, updates and deletes within a second or two.  Change Tracking reports net changes, so a row inserted then updated arrives as one `Insert` with the new values, and a row inserted then deleted arrives as one `Delete`.  The test needs Core Tools and the .NET 8 SDK on the host, and uses a throwaway login whose password exists only in a temporary `local.settings.json`, because the Functions host reads connection settings from there or from environment variables.  The script drops the login and deletes the file when it finishes.

**`DB_ID()` from `master` returns NULL for a user database, as it does in Azure.**  On a `master` connection, `DB_ID(N'appdb')` and `DB_NAME()` of that database's ID both return NULL while `sys.databases` lists it.  This is documented Azure SQL Database behaviour: [DB_ID](https://learn.microsoft.com/sql/t-sql/functions/db-id-transact-sql#remarks) returns an ID only for the current database there.  The catch is in sample code.  Microsoft's getting started guide and the Microsoft SQL agent skills create the database with `IF DB_ID('appdb') IS NULL CREATE DATABASE appdb;`, which works the first time and fails with Msg 1801 on a rerun against a persistent volume.  Where a sample wraps that guard in a wait loop with its output discarded, a rerun waits forever.  The scripts here check `sys.databases` instead, which works on the container and in Azure.

**New databases get Azure defaults.**  `appdb` came up with read committed snapshot on, accelerated database recovery on, and compatibility level 170.

**Volumes are tied to image versions.**  The image's launch script records a volume format marker and refuses volumes it doesn't support, so don't share a volume between preview builds you want to compare.  Give each its own volume.

## Troubleshooting

Symptom | Likely cause and fix
--------|---------------------
Start script fails with "application not healthy" on an existing volume | The volume's `sa` password differs from the stored credential.  See [How the password is handled](#how-the-password-is-handled).
"bind source path does not exist" | The container was restarted outside the start script.  Run the start script again.
Container stops on its own after a few seconds of inactivity | WSL shut down the idle distribution.  Start with `-KeepAlive`, or set `instanceIdleTimeout` in `%UserProfile%\.wslconfig`.
Exit code 137 | The engine was killed during shutdown.  The stop scripts allow 60 seconds; avoid `docker kill`.
Msg 40508 on `USE` | Expected on Azure SQL Database.  Connect to the database by name.
Port already in use | Start with `-Port` (or `AZSQLDB_PORT`) set to a free port.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md).  Report security problems privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Licence

MIT.  See [LICENSE](LICENSE).  The container image is Microsoft's and is covered by Microsoft's licence terms, which you accept by running it with `ACCEPT_EULA=Y`.  This repository does not redistribute it.  See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

<sub>Generated by GitHub Copilot CLI (model: claude-opus-5.5) on 2026-11-19T16:01:40-05:00, with the testing directed by Hannah Vernon.</sub>
