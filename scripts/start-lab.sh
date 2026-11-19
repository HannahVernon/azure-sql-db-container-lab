#!/usr/bin/env bash
#
# Starts the Azure SQL Database container lab on Linux or macOS.
#
# The sa password comes from standard input, so you can pipe it from a secret
# manager, or from a prompt that does not echo:
#
#   pass show azsqldb-lab/sa | ./start-lab.sh
#   ./start-lab.sh
#
# The password is written to a private temporary file (tmpfs where the system
# has one), mounted into the container as a Compose secret, and the file is
# deleted when this script exits.  It never appears on a command line, in an
# exported environment variable, in compose.yaml, or in "docker inspect".
#
# Settings, all optional and none secret:
#   AZSQLDB_PROJECT    Compose project name          (azsqldb-lab)
#   AZSQLDB_CONTAINER  container name                (azsqldb-lab)
#   AZSQLDB_VOLUME     named data volume             (azsqldb-lab-data)
#   AZSQLDB_PORT       host port on 127.0.0.1        (14331)
#   AZSQLDB_IMAGE      image, ideally pinned by digest
#   AZSQLDB_APPDB      database to create; empty to skip (appdb)
#   AZSQLDB_TIMEOUT    seconds to wait for healthy   (300)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_dir="$(cd "$here/../compose" && pwd)"

export AZSQLDB_PROJECT="${AZSQLDB_PROJECT:-azsqldb-lab}"
export AZSQLDB_CONTAINER="${AZSQLDB_CONTAINER:-azsqldb-lab}"
export AZSQLDB_VOLUME="${AZSQLDB_VOLUME:-azsqldb-lab-data}"
export AZSQLDB_PORT="${AZSQLDB_PORT:-14331}"
export AZSQLDB_IMAGE="${AZSQLDB_IMAGE:-mcr.microsoft.com/mssql/azure-sql-db-server:latest}"
database="${AZSQLDB_APPDB-appdb}"
timeout="${AZSQLDB_TIMEOUT:-300}"

name_re='^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$'
for value in "$AZSQLDB_PROJECT" "$AZSQLDB_CONTAINER" "$AZSQLDB_VOLUME"; do
    [[ "$value" =~ $name_re ]] || { echo "Invalid name: $value" >&2; exit 2; }
done
if [ -n "$database" ] && ! [[ "$database" =~ $name_re ]]; then
    echo "Invalid database name: $database" >&2; exit 2
fi
[[ "$AZSQLDB_PORT" =~ ^[0-9]{4,5}$ ]] || { echo "Invalid port: $AZSQLDB_PORT" >&2; exit 2; }

if [ -t 0 ]; then
    IFS= read -rsp 'sa password: ' pw; echo
else
    IFS= read -r pw || true
fi
pw="${pw%$'\r'}"

classes=0
[[ "$pw" =~ [A-Z] ]] && classes=$((classes + 1))
[[ "$pw" =~ [a-z] ]] && classes=$((classes + 1))
[[ "$pw" =~ [0-9] ]] && classes=$((classes + 1))
[[ "$pw" =~ [^A-Za-z0-9] ]] && classes=$((classes + 1))
if [ "${#pw}" -lt 8 ] || [ "$classes" -lt 3 ]; then
    echo "The password does not meet the sa policy: at least 8 characters, with three of upper case, lower case, digits and symbols." >&2
    exit 2
fi

base="${XDG_RUNTIME_DIR:-}"
if [ -z "$base" ] && [ -d /dev/shm ]; then base=/dev/shm; fi
base="${base:-${TMPDIR:-/tmp}}"
secret_dir="$(umask 077; mktemp -d "$base/azsqldb-lab.XXXXXX")"
trap 'rm -rf -- "$secret_dir"' EXIT

(umask 077; printf '%s' "$pw" > "$secret_dir/sa_password")
unset pw
# Readable by the container's mssql user through the mount; the directory
# keeps other local users out.
chmod 0444 "$secret_dir/sa_password"
export AZSQLDB_SECRET_FILE="$secret_dir/sa_password"

# --force-recreate: the secret's source file is new on every start and the
# previous one is gone, so the container must be recreated to mount it.  The
# databases live in the named volume and are not affected.
docker compose --project-directory "$compose_dir" -f "$compose_dir/compose.yaml" up -d --force-recreate --wait --wait-timeout "$timeout"

if [ -n "$database" ]; then
    # Guard with sys.databases, not DB_ID(): on a master connection DB_ID()
    # returns NULL for an existing user database, so a DB_ID() guard fails with
    # Msg 1801 on the second start.
    printf "IF NOT EXISTS (SELECT 1 FROM [sys].[databases] AS [d] WHERE [d].[name] = N'%s')\nBEGIN\n    CREATE DATABASE [%s];\nEND;\n" "$database" "$database" |
        docker exec -i "$AZSQLDB_CONTAINER" bash -c 'SQLCMDPASSWORD=$(cat /run/secrets/sa_password) exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -x -l 30 -d master' > /dev/null
fi

echo "Server:    127.0.0.1,$AZSQLDB_PORT"
echo "Database:  ${database:-master}"
echo "Container: $AZSQLDB_CONTAINER (image $(docker inspect --format '{{.Image}}' "$AZSQLDB_CONTAINER"))"
echo "The certificate is self-signed.  Clients need TrustServerCertificate=True, which skips"
echo "certificate validation and allows a man-in-the-middle attack: acceptable on loopback for a local lab only."
