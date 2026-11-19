#!/usr/bin/env bash
#
# Stops the Azure SQL Database container lab on Linux or macOS.
#
#   ./stop-lab.sh                    stop, keep the container and data
#   ./stop-lab.sh --remove           stop and remove the container
#   ./stop-lab.sh --remove-volume    also delete the data volume and every database in it
#
# The 60-second grace period lets the engine shut down cleanly instead of
# being killed (exit code 137).

set -euo pipefail

project="${AZSQLDB_PROJECT:-azsqldb-lab}"
[[ "$project" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo "Invalid project: $project" >&2; exit 2; }

docker compose -p "$project" stop -t 60

case "${1:-}" in
    --remove)
        docker compose -p "$project" down
        ;;
    --remove-volume)
        read -rp "Delete the data volume for '$project' and every database in it? Type yes: " answer
        if [ "$answer" = "yes" ]; then
            docker compose -p "$project" down --volumes
        else
            echo "Volume kept."
        fi
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1" >&2; exit 2
        ;;
esac
