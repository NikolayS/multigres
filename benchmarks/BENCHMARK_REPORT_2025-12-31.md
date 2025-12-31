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

---

## Multigres Setup Guide - Step by Step Reproduction

This section documents the exact steps to reproduce the Multigres benchmark, including failed attempts and fixes.

### Prerequisites Installation

```bash
# Create Hetzner VM (Ubuntu 24.04)
# SSH into the VM as root

# Install Go 1.23.4
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install PostgreSQL 18
apt-get update
apt-get install -y curl ca-certificates gnupg lsb-release
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-18

# Install etcd 3.5.17
ETCD_VER=v3.5.17
wget https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzf etcd-${ETCD_VER}-linux-amd64.tar.gz
cp etcd-${ETCD_VER}-linux-amd64/etcd* /usr/local/bin/

# Create multigres user (REQUIRED - services refuse to run as root)
useradd -m -s /bin/bash multigres
```

### Build Multigres

```bash
# Clone and build
su - multigres
git clone https://github.com/multigres/multigres.git
cd multigres
make tools
make build

# Verify binaries exist
ls bin/
# Should show: multigres multigateway multipooler pgctld multiorch multiadmin
```

### Failed Attempt 1: Using `multigres cluster start`

```bash
multigres cluster init --provisioner local
multigres cluster start
```

**Error:** etcd failed with peer URL mismatch:
```
member default has already been bootstrapped
--initial-cluster has default=http://localhost:2380 but missing from --initial-advertise-peer-urls=http://46.224.155.222:2380
```

**Root cause:** etcd auto-detects the public IP for `--initial-advertise-peer-urls` but `--initial-cluster` uses localhost.

### Failed Attempt 2: Manual etcd with env vars

```bash
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://localhost:2380 \
ETCD_ADVERTISE_CLIENT_URLS=http://localhost:2379 \
/usr/local/bin/etcd --name default ...
```

**Error:** Can't use both env vars AND command-line flags for etcd configuration.

### Working Solution: etcd with localhost-only binding

```bash
# Start etcd binding ONLY to 127.0.0.1 (prevents public IP auto-detection)
/usr/local/bin/etcd \
  --name default \
  --data-dir /home/multigres/multigres_local/data/etcd-data \
  --listen-client-urls http://127.0.0.1:2379 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --initial-cluster default=http://127.0.0.1:2380 \
  --initial-cluster-state new \
  > /home/multigres/multigres_local/logs/etcd.log 2>&1 &

# Verify etcd is healthy
etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
```

### Failed Attempt 3: Creating topology with etcdctl

```bash
etcdctl put /multigres/global/cells/zone1/Cell '{"server_addresses":["127.0.0.1:2379"]}'
```

**Error:** Multigres expects protobuf-encoded data, not JSON. Services fail with:
```
node doesn't exist: /multigres/global/cells/zone1/Cell
```

### Working Solution: Create topology via Go API

Create file `/tmp/create-topo.go`:

```go
package main

import (
    "context"
    "fmt"
    "log"
    "os"

    "github.com/multigres/multigres/go/common/topoclient"
    _ "github.com/multigres/multigres/go/common/topoclient/etcdtopo"  // CRITICAL: register etcd implementation
    clustermetadatapb "github.com/multigres/multigres/go/pb/clustermetadata"
)

func main() {
    etcdAddr := "127.0.0.1:2379"
    globalRoot := "/multigres/global"
    cellName := "zone1"
    cellRoot := "/multigres/zone1"
    database := "postgres"
    backupLocation := "/home/multigres/multigres_local/data/backups"

    ts, err := topoclient.OpenServer(topoclient.DefaultTopoImplementation, globalRoot, []string{etcdAddr}, topoclient.NewDefaultTopoConfig())
    if err != nil {
        log.Fatalf("failed to open topology server: %v", err)
    }
    defer ts.Close()

    // Delete existing entries first (recursive = true)
    ts.DeleteCell(context.Background(), cellName, true)
    ts.DeleteDatabase(context.Background(), database, true)

    // Create cell
    err = ts.CreateCell(context.Background(), cellName, &clustermetadatapb.Cell{
        ServerAddresses: []string{etcdAddr},
        Root:            cellRoot,
    })
    if err != nil {
        log.Fatalf("CreateCell error: %v", err)
    }

    // Create backup directory
    os.MkdirAll(backupLocation, 0755)

    // Create database with backup location
    err = ts.CreateDatabase(context.Background(), database, &clustermetadatapb.Database{
        Name:             database,
        BackupLocation:   backupLocation,
        DurabilityPolicy: "none",
    })
    if err != nil {
        log.Fatalf("CreateDatabase error: %v", err)
    }

    fmt.Println("Topology setup complete!")
}
```

Run from multigres directory:
```bash
cd /home/multigres/multigres
go run /tmp/create-topo.go
```

### Start Services

```bash
POOLER_DIR=/home/multigres/multigres_local/data/pooler_test
mkdir -p $POOLER_DIR/{pg_data,pg_sockets}
echo "18" > $POOLER_DIR/pg_data/PG_VERSION
mkdir -p $POOLER_DIR/pg_data/{base,global}
touch $POOLER_DIR/pg_data/postgresql.conf

# Start pgctld (as multigres user)
su - multigres -c 'nohup /home/multigres/multigres/bin/pgctld server \
  --pooler-dir /home/multigres/multigres_local/data/pooler_test \
  --pg-port 5432 \
  --grpc-port 15470 \
  --http-port 15400 \
  > /home/multigres/multigres_local/logs/pgctld.log 2>&1 &'

sleep 3

# Start multipooler
su - multigres -c 'nohup /home/multigres/multigres/bin/multipooler \
  --cell zone1 \
  --database postgres \
  --table-group default \
  --shard 0-inf \
  --pgctld-addr localhost:15470 \
  --pg-port 5432 \
  --pooler-dir /home/multigres/multigres_local/data/pooler_test \
  --grpc-port 15270 \
  --http-port 15200 \
  --topo-global-server-addresses 127.0.0.1:2379 \
  --topo-global-root /multigres/global \
  > /home/multigres/multigres_local/logs/multipooler.log 2>&1 &'

sleep 5

# Start multigateway
su - multigres -c 'nohup /home/multigres/multigres/bin/multigateway \
  --cell zone1 \
  --pg-port 15432 \
  --grpc-port 15170 \
  --http-port 15100 \
  --topo-global-server-addresses 127.0.0.1:2379 \
  --topo-global-root /multigres/global \
  > /home/multigres/multigres_local/logs/multigateway.log 2>&1 &'

sleep 5
```

### Failed Attempt 4: Query through multigateway

```bash
psql -h 127.0.0.1 -p 15432 -U postgres -c "SELECT version()" postgres
```

**Error:**
```
ERROR: query execution failed: no pooler found for target: tablegroup=default, shard=, type=PRIMARY
```

**Root cause:** Multipooler starts with type `UNKNOWN`. Multigateway looks for `PRIMARY` type.

### Working Solution: Set pooler type via RPC

Create file `/tmp/set-primary.go`:

```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"

    clustermetadatapb "github.com/multigres/multigres/go/pb/clustermetadata"
    multipoolermanagerdatapb "github.com/multigres/multigres/go/pb/multipoolermanagerdata"
    multipoolermanagerpb "github.com/multigres/multigres/go/pb/multipoolermanager"
)

func main() {
    poolerAddr := "localhost:15270"

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    conn, err := grpc.DialContext(ctx, poolerAddr, grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
    if err != nil {
        log.Fatalf("failed to connect: %v", err)
    }
    defer conn.Close()

    client := multipoolermanagerpb.NewMultiPoolerManagerClient(conn)

    _, err = client.ChangeType(ctx, &multipoolermanagerdatapb.ChangeTypeRequest{
        PoolerType: clustermetadatapb.PoolerType_PRIMARY,
    })
    if err != nil {
        log.Fatalf("ChangeType failed: %v", err)
    }

    fmt.Println("Pooler type set to PRIMARY!")
}
```

Run:
```bash
cd /home/multigres/multigres
go run /tmp/set-primary.go
```

### Fix PostgreSQL Authentication

```bash
# Update pg_hba.conf to use trust authentication
PG_HBA=/etc/postgresql/18/main/pg_hba.conf
sed -i 's/scram-sha-256/trust/g' $PG_HBA
sed -i 's/md5/trust/g' $PG_HBA
systemctl reload postgresql@18-main
```

### Verify Setup

```bash
# Test query through multigateway
psql -h 127.0.0.1 -p 15432 -U postgres -c "SELECT version()" postgres
# Should return: PostgreSQL 18.1 ... (multigres)
```

### Run Benchmark

```bash
# Initialize pgbench data (direct to PostgreSQL)
pgbench -i -s 10 -h 127.0.0.1 -p 5432 -U postgres postgres

# Benchmark through Multigres
pgbench -T 300 -P 30 -r -c 4 -j 4 -S --protocol extended \
  -h 127.0.0.1 -p 15432 -U postgres postgres

# Benchmark direct PostgreSQL (for comparison)
pgbench -T 300 -P 30 -r -c 4 -j 4 -S --protocol extended \
  -h 127.0.0.1 -p 5432 -U postgres postgres
```

---

## Open Questions for Investigation

1. **Why does performance degrade over time?** TPS dropped 53% (2,112 → 988) during 300s benchmark. Possible causes:
   - Connection pool exhaustion
   - Memory leak in multigateway/multipooler
   - etcd watch/polling overhead accumulation
   - Missing heartbeat table causing retry loops

2. **Why is the overhead so high (15x)?** Multigres adds significant latency. Areas to investigate:
   - SQL parsing overhead in multigateway
   - gRPC communication between multigateway → multipooler
   - Shard routing logic even for non-sharded workloads
   - Topology lookups for each query

3. **Is multiorch required for production?** We manually set pooler type to PRIMARY. In production, multiorch handles this automatically. The benchmark setup is minimal - production may behave differently.

4. **Would connection pooling help?** The benchmark uses 4 clients. With 100+ clients, Multigres pooling might show relative improvement vs direct PostgreSQL.

5. **What about sharded workloads?** Multigres is designed for distributed queries. Benchmarking simple SELECT on single shard doesn't show its intended use case.

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
