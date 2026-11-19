# Third-Party Notices

This repository contains only its own scripts and documentation.  It bundles no third-party code.

The lab runs on software that you install or pull separately.  This repository does not redistribute any of it.

Component | Use | Licence
----------|-----|--------
Azure SQL Database container image (`mcr.microsoft.com/mssql/azure-sql-db-server`), Microsoft | The database engine the lab runs | Microsoft's licence terms, accepted by running the image with `ACCEPT_EULA=Y`.  See Microsoft's [getting started guide](https://microsoft.github.io/azure-sql-dev-hub/container/get-started.html).
Docker Engine and Docker Compose, Docker Inc. and contributors | Container runtime and orchestration | Apache License 2.0
Windows Subsystem for Linux, Microsoft | Runs Docker on Windows | Microsoft's licence terms
ShellCheck, Vidar Holen and contributors | Development-time linting of the bash scripts only | GNU GPL v3.0
