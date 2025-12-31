#!/bin/bash
# Initialize the benchmark database
# This script runs inside the PostgreSQL container on first start

set -e

echo "Initializing benchmark database..."

# Create benchmark database if it doesn't exist
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    SELECT 'Database bench already exists' WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'bench')
    UNION ALL
    SELECT 'Creating database bench' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'bench');
EOSQL

# Initialize pgbench tables with scale factor 10
# This creates pgbench_accounts, pgbench_branches, pgbench_tellers, pgbench_history
echo "Initializing pgbench tables with scale factor 10..."
pgbench -i -s 10 -U "$POSTGRES_USER" bench

echo "Database initialization complete."
echo "Tables created:"
psql -U "$POSTGRES_USER" -d bench -c "\dt pgbench_*"
