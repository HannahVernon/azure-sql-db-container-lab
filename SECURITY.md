# Security Policy

## Scope

This repository contains a Docker Compose file, a container entrypoint wrapper, and PowerShell and bash scripts that start, stop and query a local Azure SQL Database container.  The scripts handle the container's `sa` password, so the realistic security concerns are:

- Any path by which the password reaches a command line, an environment variable of a host process, a log, `docker inspect`, a file that outlives startup, or the console.
- A script running a command it should not, for example deleting a path outside its own temporary directory, or removing a volume without the switch that asks for it.
- Guidance in the documentation that would lead a reader to weaken a connection's security beyond the local lab, such as carrying `TrustServerCertificate=True` into a connection string for a shared server.

The container image itself is Microsoft's.  Report problems in the image to Microsoft, through the links in their [getting started guide](https://microsoft.github.io/azure-sql-dev-hub/container/get-started.html#report-an-issue).

## Reporting a vulnerability

Report privately to **vuln@mvct.com**.  Please do not open a public issue for a security problem.

Include, as far as you can:

- What the problem is, and which file or script is involved
- The steps to reproduce it
- What an attacker or a careless invocation could achieve
- Your assessment of severity

Never include a real password, connection string secret or customer data in a report.

You can expect an acknowledgement within a few days.  If the report is valid, the fix and a note in the repository history will credit you unless you ask otherwise.

## Supported versions

The most recent commit on `main` is the supported version.  There are no long-lived release branches.
