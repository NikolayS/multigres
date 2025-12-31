# PostgreSQL Proxy Latency Benchmarks

This benchmark suite measures latency overhead of PostgreSQL connection poolers and proxies.

Based on methodology from:
- [postgres-ai/tests-and-benchmarks](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/63)
- [SPQR benchmarks](https://github.com/pg-sharding/benchmarks)
- [Tembo pooler benchmarks](https://legacy.tembo.io/blog/postgres-connection-poolers/)

## Systems Under Test

**Core (implemented):**
- Direct PostgreSQL (baseline)
- PgBouncer
- Multigres (multigateway → multipooler → PostgreSQL)

**Optional (TODO):**
- PgDog
- SPQR
- Citus

## Metrics Collected

- Transactions per second (TPS)
- Latency: mean, stddev, p50, p95, p99
- CPU utilization (optional)

## Test Scenarios

1. **Simple SELECT** (`SELECT 1`) - measures pure proxy overhead
2. **pgbench default** - standard OLTP workload
3. **Read-only** - SELECT-heavy workload
4. **Connection scaling** - varying client counts (10, 50, 100, 250, 500, 1000)

## Prerequisites

- Docker and Docker Compose
- PostgreSQL client tools (`pgbench`, `psql`)
- Built multigres binaries (`make build`)

## Quick Start

```bash
# Start all services
cd benchmarks
docker compose up -d

# Wait for services to be ready
./scripts/wait-for-services.sh

# Run benchmarks
./scripts/run-benchmarks.sh

# View results
./scripts/analyze-results.sh

# Cleanup
docker compose down -v
```

## Configuration

Edit `config/benchmark.env` to customize:
- `PGBENCH_SCALE` - Database scale factor (default: 10)
- `PGBENCH_TIME` - Duration per test in seconds (default: 60)
- `PGBENCH_CLIENTS` - Client counts to test (default: "10 50 100 250 500")
- `WARMUP_TIME` - Warmup duration in seconds (default: 10)

## Directory Structure

```
benchmarks/
├── config/
│   ├── benchmark.env         # Benchmark parameters
│   ├── pgbouncer.ini         # PgBouncer configuration
│   ├── multigres.yaml        # Multigres cluster configuration
│   └── postgresql.conf       # PostgreSQL tuning
├── scripts/
│   ├── run-benchmarks.sh     # Main benchmark runner
│   ├── run-single-bench.sh   # Single benchmark execution
│   ├── wait-for-services.sh  # Health check script
│   ├── analyze-results.sh    # Results analysis
│   └── init-db.sh            # Database initialization
├── results/                  # Benchmark results (gitignored)
├── docker-compose.yaml       # Service definitions
└── README.md
```

## Adding New Poolers

To add a new pooler (e.g., PgDog):

1. Add service definition to `docker-compose.yaml`
2. Add configuration to `config/`
3. Add entry to `TARGETS` in `scripts/run-benchmarks.sh`
4. Run benchmarks

## Interpreting Results

The `analyze-results.sh` script produces:
- Summary table comparing all systems
- Latency overhead percentage vs direct PostgreSQL
- Charts (if gnuplot available)

Lower latency and higher TPS indicate better performance.
The key metric is **overhead percentage** - how much slower the proxy is compared to direct PostgreSQL.
