#!/usr/bin/env bash
#
# Runs T-SQL in the Azure SQL Database container lab on Linux or macOS.
#
#   ./invoke-lab-sql.sh ../sql/build-check.sql
#   ./invoke-lab-sql.sh -d appdb my-migration.sql
#   echo "SELECT DB_NAME();" | ./invoke-lab-sql.sh -d appdb
#
# The T-SQL goes to the sqlcmd bundled in the container over standard input.
# The sa password comes from the Compose secret inside the container.
# Scripting variables are disabled (-x) and sqlcmd stops on the first error (-b).
# Azure SQL Database does not support USE: pick the database with -d.

set -euo pipefail

database=master
container="${AZSQLDB_CONTAINER:-azsqldb-lab}"
while getopts 'd:c:' opt; do
    case "$opt" in
        d) database="$OPTARG" ;;
        c) container="$OPTARG" ;;
        *) echo "Usage: $0 [-d database] [-c container] [file.sql]" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

name_re='^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$'
[[ "$database" =~ $name_re ]] || { echo "Invalid database name: $database" >&2; exit 2; }
[[ "$container" =~ $name_re ]] || { echo "Invalid container name: $container" >&2; exit 2; }

run_sql() {
    docker exec -i "$container" bash -c 'SQLCMDPASSWORD=$(cat /run/secrets/sa_password) exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -x -W -l 30 -d "$1"' sqlcmd "$database"
}

if [ $# -gt 0 ]; then
    run_sql < "$1"
else
    run_sql
fi
