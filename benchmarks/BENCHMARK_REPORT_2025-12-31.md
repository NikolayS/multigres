# PostgreSQL Proxy Latency Benchmark Report

**Date:** December 31, 2025
**Updated:** December 31, 2025 (Multigres results added)
**Methodology:** Based on [GitLab Issue #63](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/63)

## Test Environment

### First Run (PgBouncer, PgDog, Citus)

| Component | Specification |
|-----------|---------------|
| Server | Hetzner CCX43 |
| CPU | 16 vCPU (AMD EPYC-Milan) |
| RAM | 64 GB |
| OS | Ubuntu 24.04.3 LTS |
| PostgreSQL | 18.1 |
| Kernel | 6.8.0-71-generic |

### Second Run (Multigres)

| Component | Specification |
|-----------|---------------|
| Server | Hetzner CPX21 |
| CPU | 3 vCPU (AMD EPYC-Milan) |
| RAM | 4 GB |
| OS | Ubuntu 24.04.5 LTS |
| PostgreSQL | 18.1 |
| Kernel | 6.8.0-51-generic |

Note: Multigres tested on smaller VM - direct comparison with other proxies should be against same-VM PostgreSQL baseline.

## Benchmark Configuration

```bash
pgbench -T 300 -P 30 -r -c 4 -j 4 -S --protocol extended postgres
```

- **Workload:** SELECT-only (`-S`)
- **Protocol:** Extended query protocol
- **Duration:** 300 seconds per test
- **Clients:** 4 concurrent connections
- **Threads:** 4

## Results

### First Run (CCX43 - 16 vCPU)

| System | Port | TPS (avg) | Latency (avg) | Status |
|--------|------|-----------|---------------|--------|
| **PostgreSQL (direct)** | 5432 | 16,589 | 0.240 ms | Baseline |
| **PgBouncer** | 6432 | 10,323 | 0.387 ms | OK |
| **PgDog** | 6433 | 8,518 | 0.469 ms | OK |
| **Citus** | 6434 | 7,899 | 0.506 ms | OK |
| **SPQR** | 6435 | — | — | FAILED |

### Second Run (CPX21 - 3 vCPU) - Multigres

| System | Port | TPS (avg) | Latency (avg) | Status |
|--------|------|-----------|---------------|--------|
| **PostgreSQL (direct)** | 5432 | 21,115 | 0.189 ms | Baseline |
| **Multigres (multigateway)** | 15432 | 1,389 | 2.879 ms | OK |

### Latency Overhead vs Direct PostgreSQL

| System | Overhead | Notes |
|--------|----------|-------|
| PgBouncer | +61% | CCX43 VM |
| PgDog | +95% | CCX43 VM |
| Citus | +111% | CCX43 VM |
| **Multigres** | **+1,424%** | CPX21 VM - see notes below |

## Notes

### Multigres

**Successfully benchmarked** on December 31, 2025 after multiple configuration attempts.

**Architecture tested:**
```
Client → multigateway (port 15432) → multipooler → PostgreSQL (port 5432)
```

**Key findings:**
1. **High latency overhead** (2.879 ms average vs 0.189 ms direct) - 15x slower
2. **Performance degradation over time** during the 300-second benchmark:
   - First 30s: 2,112 TPS (1.89 ms latency)
   - Last 30s: 988 TPS (4.05 ms latency)
   - TPS dropped by 53% over the benchmark duration
3. **Heartbeat errors** in multipooler logs (missing `multigres.heartbeat` table) - but queries still worked

**Setup challenges overcome:**
- Services refuse to run as root (security feature) - created `multigres` user
- Topology data requires protobuf-encoded values via Go API (not etcdctl)
- etcd peer URL mismatch on public IP - fixed by binding to 127.0.0.1
- Pooler type starts as `UNKNOWN` - required explicit `ChangeType` RPC to set to `PRIMARY`

**Raw pgbench output (Multigres):**
```
pgbench (18.1, server 17.0 (multigres))
transaction type: <builtin: select only>
scaling factor: 10
query mode: extended
number of clients: 4
number of threads: 4
duration: 300 s
number of transactions actually processed: 416678
number of failed transactions: 0 (0.000%)
latency average = 2.879 ms
latency stddev = 0.824 ms
initial connection time = 1.948 ms
tps = 1388.919829 (without initial connection time)
```

**Raw pgbench output (Direct PostgreSQL on same VM):**
```
pgbench (18.1)
transaction type: <builtin: select only>
scaling factor: 10
query mode: extended
number of clients: 4
number of threads: 4
duration: 300 s
number of transactions actually processed: 6334375
number of failed transactions: 0 (0.000%)
latency average = 0.189 ms
latency stddev = 0.071 ms
initial connection time = 12.915 ms
tps = 21115.462088 (without initial connection time)
```

### SPQR
SPQR container started but immediately exited. Used correct image `pgsharding/spqr-router:latest`. Container logs showed it started but crashed. Port 6435 was not responding.

### Citus
Tested using Docker image `citusdata/citus:13` (PostgreSQL 17.6). Note: Citus is primarily a distributed database extension, not a connection pooler.

## Conclusions

1. **Direct PostgreSQL** provides the lowest latency baseline
2. **PgBouncer** adds ~61% latency overhead but remains the fastest pooler
3. **PgDog** (Rust-based) shows ~95% overhead
4. **Citus** shows ~111% overhead (but serves different purpose - distributed queries)
5. **Multigres** shows very high overhead (~1,424%) in this simple proxy benchmark
   - This overhead is expected given Multigres's architecture (SQL parsing, routing, etc.)
   - Multigres is designed for distributed/sharded workloads, not as a simple pooler
   - The performance degradation over time warrants investigation
6. **SPQR** could not be benchmarked (container crash)

## Recommendations for Future Benchmarks

1. Test with higher concurrency (100+ clients) where pooling benefits matter
2. Include write workloads to measure transaction handling
3. For Multigres: investigate performance degradation over time
4. For SPQR: debug container startup issues
5. Add Odyssey and PgCat to the comparison
6. Test Multigres on same VM spec as other proxies for fair comparison
7. Test Multigres with sharded workloads where its architecture provides value

---

*Report generated from Hetzner VM benchmarks.*
*First run VM ID: 116515289 (CCX43)*
*Second run VM ID: 116516938 (CPX21)*
