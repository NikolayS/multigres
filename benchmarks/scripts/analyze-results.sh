#!/bin/bash
# Analyze benchmark results and generate comparison report

set -e

RESULTS_FILE=${1:-./results/latest/results.csv}

if [ ! -f "$RESULTS_FILE" ]; then
    echo "Error: Results file not found: $RESULTS_FILE"
    echo "Usage: $0 [results.csv]"
    exit 1
fi

echo "=============================================="
echo "Benchmark Results Analysis"
echo "=============================================="
echo ""
echo "Results file: $RESULTS_FILE"
echo ""

# Use awk for analysis (portable)
awk -F',' '
BEGIN {
    print "=== Average Results by Target and Test Type ==="
    print ""
    printf "%-12s %-10s %8s %10s %10s %10s %10s %10s\n", \
        "Target", "Test", "Clients", "TPS", "Avg(ms)", "P50(ms)", "P95(ms)", "P99(ms)"
    print "--------------------------------------------------------------------------------"
}

NR == 1 { next }  # Skip header

{
    target = $1
    test_type = $2
    clients = $3
    tps = $4
    latency_avg = $5
    latency_p50 = $7
    latency_p95 = $8
    latency_p99 = $9

    key = target ":" test_type ":" clients

    tps_sum[key] += tps
    avg_sum[key] += latency_avg
    p50_sum[key] += latency_p50
    p95_sum[key] += latency_p95
    p99_sum[key] += latency_p99
    count[key]++

    targets[target] = 1
    tests[test_type] = 1
    client_counts[clients] = 1
}

END {
    # Sort and print results
    n = asorti(count, sorted_keys)

    for (i = 1; i <= n; i++) {
        key = sorted_keys[i]
        split(key, parts, ":")
        target = parts[1]
        test_type = parts[2]
        clients = parts[3]

        c = count[key]
        printf "%-12s %-10s %8d %10.1f %10.2f %10.2f %10.2f %10.2f\n", \
            target, test_type, clients, \
            tps_sum[key]/c, \
            avg_sum[key]/c, \
            p50_sum[key]/c, \
            p95_sum[key]/c, \
            p99_sum[key]/c
    }

    print ""
    print "=== Overhead Comparison vs Direct PostgreSQL ==="
    print ""
    printf "%-12s %-10s %8s %12s %12s\n", \
        "Target", "Test", "Clients", "TPS Ratio", "Latency Overhead"
    print "--------------------------------------------------------------"

    for (i = 1; i <= n; i++) {
        key = sorted_keys[i]
        split(key, parts, ":")
        target = parts[1]
        test_type = parts[2]
        clients = parts[3]

        if (target == "postgres") continue

        pg_key = "postgres:" test_type ":" clients
        if (!(pg_key in count)) continue

        c = count[key]
        pg_c = count[pg_key]

        target_tps = tps_sum[key]/c
        pg_tps = tps_sum[pg_key]/pg_c

        target_lat = avg_sum[key]/c
        pg_lat = avg_sum[pg_key]/pg_c

        if (pg_tps > 0 && pg_lat > 0) {
            tps_ratio = target_tps / pg_tps
            lat_overhead = ((target_lat - pg_lat) / pg_lat) * 100

            printf "%-12s %-10s %8d %11.1f%% %11.1f%%\n", \
                target, test_type, clients, \
                tps_ratio * 100, lat_overhead
        }
    }

    print ""
    print "=== Summary ==="
    print ""

    # Calculate overall averages per target
    for (t in targets) {
        total_tps = 0
        total_lat = 0
        total_count = 0

        for (key in count) {
            split(key, parts, ":")
            if (parts[1] == t) {
                c = count[key]
                total_tps += tps_sum[key]
                total_lat += avg_sum[key]
                total_count += c
            }
        }

        if (total_count > 0) {
            printf "%-12s: Avg TPS: %10.1f, Avg Latency: %8.2f ms\n", \
                t, total_tps/total_count, total_lat/total_count
        }
    }
}
' "$RESULTS_FILE"

echo ""
echo "=============================================="
