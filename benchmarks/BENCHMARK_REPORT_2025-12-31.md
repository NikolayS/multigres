# PostgreSQL Proxy Latency Benchmark Report

**Date:** December 31, 2025
**Methodology:** Based on [GitLab Issue #63](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/63)

## Test Environment

| Component | Specification |
|-----------|---------------|
| Server | Hetzner CCX43 |
| CPU | 16 vCPU (AMD EPYC-Milan) |
| RAM | 64 GB |
| OS | Ubuntu 24.04.3 LTS |
| PostgreSQL | 18 (beta) |
| Kernel | 6.8.0-90-generic |

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

| System | Port | TPS (avg) | Latency (avg) | Status |
|--------|------|-----------|---------------|--------|
| **PostgreSQL (direct)** | 5432 | 18,702 | 0.214 ms | Baseline |
| **PgBouncer** | 6432 | 10,770 | 0.371 ms | OK |
| **PgDog** | 6433 | 9,070 | 0.440 ms | OK |
| **Citus** | 6434 | 8,432 | 0.474 ms | OK |
| **SPQR** | 6435 | — | — | FAILED |
| **Multigres** | — | — | — | NOT TESTED |

### Latency Overhead vs Direct PostgreSQL

| System | Overhead |
|--------|----------|
| PgBouncer | +73% |
| PgDog | +106% |
| Citus | +121% |

## Notes

### SPQR
SPQR Docker container failed to start. The Docker image pull failed with:
```
docker pull pg-sharding/spqr-router:latest
docker pull ghcr.io/pg-sharding/spqr-router:latest
```
Both attempts failed, preventing SPQR from being benchmarked.

### Multigres

**Multigres was not benchmarked** because it is architecturally different from the other systems tested.

Multigres is a **distributed PostgreSQL cluster orchestration platform** (similar to Vitess for MySQL), not a simple connection pooler or proxy. Its architecture requires:

1. **etcd** for topology and service discovery
2. **pgctld** for PostgreSQL lifecycle management
3. **multipooler** for connection pooling (connects to pgctld via gRPC)
4. **multigateway** for accepting client connections
5. **multiorch** for consensus and failover

This multi-service architecture is designed for:
- Horizontal scaling across multiple PostgreSQL nodes
- Automatic failover and leader election
- Sharding and query routing across table groups

**Comparing Multigres to PgBouncer/PgDog in a single-node latency test would be misleading** because:
- Multigres adds coordination overhead for features not being tested
- The primary value proposition (cluster orchestration) isn't measured
- A fair comparison would require a multi-node setup with failover scenarios

### Citus
Citus was tested using the official Docker image (`citusdata/citus:13`). Note that Citus is primarily a distributed database extension, so comparing it as a "proxy" is also somewhat misleading—it's included here for reference only.

## Conclusions

1. **Direct PostgreSQL** provides the lowest latency baseline (0.214 ms)
2. **PgBouncer** adds ~73% latency overhead but remains the fastest pooler tested
3. **PgDog** (Rust-based) shows ~106% overhead, competitive for a newer project
4. **Citus** shows higher overhead but serves a different purpose (distributed queries)

## Recommendations for Future Benchmarks

1. Test with higher concurrency (100+ clients) where pooling benefits become apparent
2. Include write workloads to measure transaction handling
3. Test Multigres in a proper multi-node cluster configuration
4. Re-attempt SPQR with manual container setup
5. Add Odyssey and PgCat to the comparison

---

*Report generated from Hetzner VM benchmarks. VM ID: 116513839*
