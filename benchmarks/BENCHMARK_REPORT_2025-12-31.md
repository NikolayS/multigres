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
| PostgreSQL | 18.1 |
| Kernel | 6.8.0-71-generic |

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
| **PostgreSQL (direct)** | 5432 | 16,589 | 0.240 ms | Baseline |
| **PgBouncer** | 6432 | 10,323 | 0.387 ms | OK |
| **PgDog** | 6433 | 8,518 | 0.469 ms | OK |
| **Citus** | 6434 | 7,899 | 0.506 ms | OK |
| **SPQR** | 6435 | — | — | FAILED |
| **Multigres** | — | — | — | FAILED |

### Latency Overhead vs Direct PostgreSQL

| System | Overhead |
|--------|----------|
| PgBouncer | +61% |
| PgDog | +95% |
| Citus | +111% |

## Notes

### SPQR
SPQR container started but immediately exited. Used correct image `pgsharding/spqr-router:latest`. Container logs showed it started but crashed. Port 6435 was not responding.

### Multigres

**Failed to configure after multiple attempts.**

Multigres has a proxy layer (`multigateway`) that should be benchmarked. Setup requires:
1. etcd for topology storage
2. pgctld for PostgreSQL lifecycle management
3. multipooler for connection pooling
4. multigateway for accepting client connections

**Issues encountered:**
- Services refuse to run as root (security feature) - requires non-root user
- Topology data must be protobuf-encoded, not JSON - can't use etcdctl directly
- `multigres cluster start` failed due to etcd peer URL mismatch on public IP
- Shard format validation (`0-inf` required for default tablegroup)
- Cell topology structure requires specific protobuf schema

**Conclusion:** Multigres is designed for production cluster orchestration, not ad-hoc benchmarking. A proper benchmark requires either:
- Using the integration test harness (Go code)
- Setting up a development environment with all dependencies
- Fixing the `cluster start` etcd configuration for public IPs

### Citus
Tested using Docker image `citusdata/citus:13` (PostgreSQL 17.6). Note: Citus is primarily a distributed database extension, not a connection pooler.

## Conclusions

1. **Direct PostgreSQL** provides the lowest latency baseline (0.240 ms)
2. **PgBouncer** adds ~61% latency overhead but remains the fastest pooler
3. **PgDog** (Rust-based) shows ~95% overhead
4. **Citus** shows ~111% overhead (but serves different purpose - distributed queries)
5. **SPQR** and **Multigres** could not be benchmarked in this test

## Recommendations for Future Benchmarks

1. Test with higher concurrency (100+ clients) where pooling benefits matter
2. Include write workloads to measure transaction handling
3. For Multigres: use integration test harness or fix etcd config
4. For SPQR: debug container startup issues
5. Add Odyssey and PgCat to the comparison

---

*Report generated from Hetzner VM benchmarks. VM ID: 116515289*
