#!/bin/bash
# Hetzner VM Setup Script for PostgreSQL Proxy Latency Benchmark
# Based on methodology from gitlab.com/postgres-ai/.../issues/63

set -e
exec > >(tee /root/benchmark.log) 2>&1

echo "=== Starting benchmark setup at $(date) ==="

# Install dependencies
apt-get update
apt-get install -y curl wget gnupg2 lsb-release git make golang-go docker.io docker-compose-v2

# Start Docker
systemctl start docker
systemctl enable docker

# Install PostgreSQL 18
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-18 postgresql-client-18

# Configure PostgreSQL for benchmarking
cat > /etc/postgresql/18/main/conf.d/benchmark.conf << 'EOF'
listen_addresses = '*'
max_connections = 500
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 64MB
synchronous_commit = off
fsync = off
full_page_writes = off
EOF

# Allow password auth
echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/18/main/pg_hba.conf
echo "host all all 172.0.0.0/8 md5" >> /etc/postgresql/18/main/pg_hba.conf

systemctl restart postgresql@18-main

# Set postgres password
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"

# Initialize pgbench
export PGPASSWORD=postgres
pgbench -i -s 1 -h 127.0.0.1 -p 5432 -U postgres postgres

# Install PgBouncer
apt-get install -y pgbouncer

cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
postgres = host=127.0.0.1 port=5432 dbname=postgres

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 100
max_client_conn = 10000
EOF

echo '"postgres" "postgres"' > /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/userlist.txt
systemctl restart pgbouncer

# Setup Docker containers for PgDog, SPQR, Citus
mkdir -p /root/benchmark

# PgDog setup
cat > /root/benchmark/docker-compose.yml << 'EOF'
services:
  pgdog:
    image: ghcr.io/pgdogdev/pgdog:main
    ports:
      - "6433:6432"
    volumes:
      - ./pgdog.toml:/pgdog/pgdog.toml
      - ./users.toml:/pgdog/users.toml
    network_mode: host

  spqr-router:
    image: pg-sharding/spqr-router:latest
    ports:
      - "6435:6432"
    volumes:
      - ./spqr-router.yaml:/etc/spqr/router.yaml
    environment:
      - SPQR_ROUTER_CONFIG=/etc/spqr/router.yaml
    network_mode: host

  citus:
    image: citusdata/citus:13
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "6434:5432"
    command: ["postgres", "-c", "max_connections=500"]
EOF

cat > /root/benchmark/pgdog.toml << 'EOF'
[general]
host = "0.0.0.0"
port = 6432
default_pool_size = 100
prepared_statements = "disabled"
workers = 4

[[databases]]
name = "postgres"
host = "127.0.0.1"
port = 5432
EOF

cat > /root/benchmark/users.toml << 'EOF'
[[users]]
name = "postgres"
password = "postgres"
database = "postgres"
EOF

cat > /root/benchmark/spqr-router.yaml << 'EOF'
host: '0.0.0.0'
router_port: '6432'
admin_console_port: '7000'
router_mode: PROXY
log_level: error

frontend_rules:
  - usr: postgres
    db: postgres
    pool_mode: TRANSACTION
    auth_rule:
      auth_method: ok

backend_rules:
  - usr: postgres
    db: postgres
    auth_rule:
      auth_method: md5
      password: postgres

shards:
  shard1:
    db: postgres
    usr: postgres
    pwd: postgres
    hosts:
      - '127.0.0.1:5432'
EOF

cd /root/benchmark
docker compose pull 2>/dev/null || true
docker compose up -d 2>/dev/null || true

# Wait for services
sleep 10

# Clone and build Multigres
cd /root
git clone https://github.com/multigres/multigres.git || true
cd /root/multigres
make build 2>/dev/null || echo "Multigres build may need additional setup"

echo "=== Setup complete at $(date) ==="

# Run benchmarks
echo ""
echo "=== Starting benchmarks at $(date) ==="

RESULTS_FILE=/root/benchmark-results.txt
> $RESULTS_FILE

run_bench() {
    local name=$1
    local port=$2
    echo "Testing $name on port $port..."

    if PGPASSWORD=postgres pg_isready -h 127.0.0.1 -p $port -U postgres -q 2>/dev/null; then
        echo "=== $name (port $port) ===" >> $RESULTS_FILE
        PGPASSWORD=postgres pgbench -h 127.0.0.1 -p $port -U postgres \
            -T 60 -P 10 -r -c 4 -j 4 -S --protocol extended postgres 2>&1 | tee -a $RESULTS_FILE
        echo "" >> $RESULTS_FILE
    else
        echo "$name not available on port $port" >> $RESULTS_FILE
    fi
}

# Run benchmarks
run_bench "Direct PostgreSQL" 5432
run_bench "PgBouncer" 6432
run_bench "PgDog" 6433
run_bench "Citus" 6434
run_bench "SPQR" 6435

echo "=== Benchmarks complete at $(date) ===" >> $RESULTS_FILE

# Start simple HTTP server to serve results
cd /root
python3 -m http.server 8080 &

echo ""
echo "=== All done! Results available at http://$(hostname -I | awk '{print $1}'):8080/benchmark-results.txt ==="
