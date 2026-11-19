#!/bin/bash
#
# Entrypoint wrapper for the Azure SQL Database container.
#
# The image reads the sa password only from the MSSQL_SA_PASSWORD environment
# variable.  Passing it with "docker run -e" or in a Compose "environment:"
# block stores it in the container's configuration, where "docker inspect"
# shows it.  This wrapper reads it from the Compose secret instead and exports
# it for the engine's process tree only, then hands over to the image's own
# entrypoint.
#
# The engine uses MSSQL_SA_PASSWORD when it initializes a new data volume.  On
# an existing volume the current sa password is kept.

set -euo pipefail

secret_file=/run/secrets/sa_password

if [ -r "$secret_file" ]; then
    MSSQL_SA_PASSWORD="$(tr -d '\r\n' < "$secret_file")"
    export MSSQL_SA_PASSWORD
else
    echo "sqldb-entrypoint: $secret_file is missing or unreadable; starting without MSSQL_SA_PASSWORD." >&2
fi

exec /opt/mssql/bin/launch_sqlservr.sh "$@"
