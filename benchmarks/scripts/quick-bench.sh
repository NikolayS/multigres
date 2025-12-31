#!/bin/bash
# Quick benchmark script for local testing
# Usage: ./quick-bench.sh [postgres|pgbouncer|multigres] [clients]

set -e

TARGET=${1:-postgres}
CLIENTS=${2:-10}
TIME=${3:-30}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/benchmark.env" 2>/dev/null || true

# Default ports if not set
POSTGRES_PORT=${POSTGRES_PORT:-5432}
PGBOUNCER_PORT=${PGBOUNCER_PORT:-6432}
MULTIGRES_PORT=${MULTIGRES_PORT:-15432}
HOST=${HOST:-localhost}

case $TARGET in
    postgres|pg|direct)
        PORT=$POSTGRES_PORT
        NAME="postgres"
        ;;
    pgbouncer|bouncer|pb)
        PORT=$PGBOUNCER_PORT
        NAME="pgbouncer"
        ;;
    multigres|mg)
        PORT=$MULTIGRES_PORT
        NAME="multigres"
        ;;
    *)
        echo "Usage: $0 [postgres|pgbouncer|multigres] [clients] [time]"
        echo ""
        echo "Examples:"
        echo "  $0 postgres 50 30    # Test direct PostgreSQL with 50 clients for 30s"
        echo "  $0 pgbouncer 100     # Test PgBouncer with 100 clients"
        echo "  $0 multigres         # Test Multigres with default 10 clients"
        exit 1
        ;;
esac

echo "=============================================="
echo "Quick Benchmark: ${NAME}"
echo "=============================================="
echo "Host: ${HOST}:${PORT}"
echo "Clients: ${CLIENTS}"
echo "Duration: ${TIME}s"
echo ""

# Check connectivity
if ! pg_isready -h "$HOST" -p "$PORT" -U postgres -q 2>/dev/null; then
    echo "Error: Cannot connect to ${NAME} at ${HOST}:${PORT}"
    echo "Make sure the service is running."
    exit 1
fi

echo "=== Test 1: Simple SELECT 1 (pure overhead) ==="
echo ""
echo "SELECT 1;" | pgbench -h "$HOST" -p "$PORT" -U postgres -d bench \
    -c "$CLIENTS" -j 4 -T "$TIME" -P 5 -S -f /dev/stdin

echo ""
echo "=== Test 2: Default TPC-B workload ==="
echo ""
pgbench -h "$HOST" -p "$PORT" -U postgres -d bench \
    -c "$CLIENTS" -j 4 -T "$TIME" -P 5

echo ""
echo "=== Test 3: Read-only workload ==="
echo ""
pgbench -h "$HOST" -p "$PORT" -U postgres -d bench \
    -c "$CLIENTS" -j 4 -T "$TIME" -P 5 -S

echo ""
echo "Benchmark complete for ${NAME}"
