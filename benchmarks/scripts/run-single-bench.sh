#!/bin/bash
# Run a single pgbench test and output results in a parseable format

set -e

usage() {
    echo "Usage: $0 -h HOST -p PORT -n NAME -c CLIENTS -t TIME -T TYPE [-w WARMUP] [-j JOBS]"
    echo ""
    echo "Options:"
    echo "  -h HOST    Database host"
    echo "  -p PORT    Database port"
    echo "  -n NAME    Target name (for output)"
    echo "  -c CLIENTS Number of clients"
    echo "  -t TIME    Test duration in seconds"
    echo "  -T TYPE    Test type: simple, default, readonly"
    echo "  -w WARMUP  Warmup time in seconds (default: 10)"
    echo "  -j JOBS    Number of threads (default: 4)"
    exit 1
}

# Defaults
WARMUP=10
JOBS=4
PGUSER=${PGUSER:-postgres}
PGDATABASE=${PGDATABASE:-bench}

while getopts "h:p:n:c:t:T:w:j:" opt; do
    case $opt in
        h) HOST=$OPTARG ;;
        p) PORT=$OPTARG ;;
        n) NAME=$OPTARG ;;
        c) CLIENTS=$OPTARG ;;
        t) TIME=$OPTARG ;;
        T) TYPE=$OPTARG ;;
        w) WARMUP=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$HOST" ] || [ -z "$PORT" ] || [ -z "$NAME" ] || [ -z "$CLIENTS" ] || [ -z "$TIME" ] || [ -z "$TYPE" ]; then
    usage
fi

# Build pgbench command based on test type
case $TYPE in
    simple)
        # Simple SELECT 1 - measures pure proxy overhead
        PGBENCH_OPTS="-S -f /dev/stdin"
        SCRIPT="SELECT 1;"
        ;;
    default)
        # Default TPC-B like workload
        PGBENCH_OPTS=""
        SCRIPT=""
        ;;
    readonly)
        # Read-only workload (SELECT only)
        PGBENCH_OPTS="-S"
        SCRIPT=""
        ;;
    *)
        echo "Unknown test type: $TYPE"
        exit 1
        ;;
esac

# Create temp file for results
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# Run warmup if requested
if [ "$WARMUP" -gt 0 ]; then
    echo "# Warming up for ${WARMUP}s..." >&2
    if [ "$TYPE" = "simple" ]; then
        echo "$SCRIPT" | pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
            -c "$CLIENTS" -j "$JOBS" -T "$WARMUP" $PGBENCH_OPTS >/dev/null 2>&1 || true
    else
        pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
            -c "$CLIENTS" -j "$JOBS" -T "$WARMUP" $PGBENCH_OPTS >/dev/null 2>&1 || true
    fi
fi

# Run the actual benchmark
echo "# Running ${TYPE} benchmark: ${NAME} with ${CLIENTS} clients for ${TIME}s..." >&2

if [ "$TYPE" = "simple" ]; then
    echo "$SCRIPT" | pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
        -c "$CLIENTS" -j "$JOBS" -T "$TIME" -P 5 --log --log-prefix="$TMPFILE" \
        $PGBENCH_OPTS 2>&1 | tee "${TMPFILE}.out"
else
    pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
        -c "$CLIENTS" -j "$JOBS" -T "$TIME" -P 5 --log --log-prefix="$TMPFILE" \
        $PGBENCH_OPTS 2>&1 | tee "${TMPFILE}.out"
fi

# Parse and output results
OUTPUT="${TMPFILE}.out"

# Extract metrics from pgbench output
TPS=$(grep "tps = " "$OUTPUT" | tail -1 | sed 's/.*tps = \([0-9.]*\).*/\1/')
LATENCY_AVG=$(grep "latency average" "$OUTPUT" | sed 's/.*= \([0-9.]*\) ms.*/\1/')
LATENCY_STDDEV=$(grep "latency stddev" "$OUTPUT" | sed 's/.*= \([0-9.]*\) ms.*/\1/')

# Calculate percentiles from log file if available
LOGFILE=$(ls ${TMPFILE}.* 2>/dev/null | grep -v ".out" | head -1)
if [ -n "$LOGFILE" ] && [ -f "$LOGFILE" ]; then
    # Log format: client_id transaction_no time usec_since_epoch latency
    # Column 4 is latency in microseconds
    SORTED=$(sort -t' ' -k4 -n "$LOGFILE")
    TOTAL=$(echo "$SORTED" | wc -l)

    if [ "$TOTAL" -gt 0 ]; then
        P50_LINE=$((TOTAL * 50 / 100))
        P95_LINE=$((TOTAL * 95 / 100))
        P99_LINE=$((TOTAL * 99 / 100))

        P50=$(echo "$SORTED" | sed -n "${P50_LINE}p" | awk '{print $4/1000}')
        P95=$(echo "$SORTED" | sed -n "${P95_LINE}p" | awk '{print $4/1000}')
        P99=$(echo "$SORTED" | sed -n "${P99_LINE}p" | awk '{print $4/1000}')
    fi
    rm -f "$LOGFILE"
fi

# Output in CSV format
echo ""
echo "# Results (CSV format):"
echo "target,test_type,clients,tps,latency_avg_ms,latency_stddev_ms,latency_p50_ms,latency_p95_ms,latency_p99_ms"
echo "${NAME},${TYPE},${CLIENTS},${TPS:-0},${LATENCY_AVG:-0},${LATENCY_STDDEV:-0},${P50:-0},${P95:-0},${P99:-0}"
