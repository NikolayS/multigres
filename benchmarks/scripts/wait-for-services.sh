#!/bin/bash
# Wait for all benchmark services to be ready

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/benchmark.env"

MAX_WAIT=120
INTERVAL=2

wait_for_port() {
    local host=$1
    local port=$2
    local name=$3
    local waited=0

    echo -n "Waiting for ${name} (${host}:${port})..."

    while ! pg_isready -h "$host" -p "$port" -U postgres -q 2>/dev/null; do
        if [ $waited -ge $MAX_WAIT ]; then
            echo " TIMEOUT"
            return 1
        fi
        sleep $INTERVAL
        waited=$((waited + INTERVAL))
        echo -n "."
    done
    echo " ready"
    return 0
}

echo "Checking service health..."
echo "=========================="

# Check PostgreSQL
wait_for_port "$POSTGRES_HOST" "$POSTGRES_PORT" "PostgreSQL" || exit 1

# Check PgBouncer
wait_for_port "$PGBOUNCER_HOST" "$PGBOUNCER_PORT" "PgBouncer" || exit 1

# Check Multigres (may take longer to initialize)
echo -n "Waiting for Multigres (${MULTIGRES_HOST}:${MULTIGRES_PORT})..."
waited=0
while ! pg_isready -h "$MULTIGRES_HOST" -p "$MULTIGRES_PORT" -U postgres -q 2>/dev/null; do
    if [ $waited -ge $MAX_WAIT ]; then
        echo " TIMEOUT (Multigres may need manual setup)"
        echo "Note: Multigres requires topology initialization. See README for details."
        break
    fi
    sleep $INTERVAL
    waited=$((waited + INTERVAL))
    echo -n "."
done
if [ $waited -lt $MAX_WAIT ]; then
    echo " ready"
fi

echo ""
echo "Service check complete."

# Verify database has pgbench tables
echo ""
echo "Verifying pgbench tables..."
if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U postgres -d bench -c "SELECT count(*) FROM pgbench_accounts" >/dev/null 2>&1; then
    echo "pgbench tables verified."
else
    echo "Warning: pgbench tables not found. Run: pgbench -i -s 10 -h localhost -p 5432 -U postgres bench"
fi
