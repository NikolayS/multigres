#!/bin/bash
# Run a single pgbench test and output results in a parseable format
# Based on methodology from:
# https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/63

set -e

usage() {
    echo "Usage: $0 -h HOST -p PORT -n NAME -c CLIENTS -t TIME -T TYPE [-j JOBS] [-P PROGRESS] [-r PROTOCOL]"
    echo ""
    echo "Options:"
    echo "  -h HOST      Database host"
    echo "  -p PORT      Database port"
    echo "  -n NAME      Target name (for output)"
    echo "  -c CLIENTS   Number of clients (default: 4)"
    echo "  -t TIME      Test duration in seconds (default: 300)"
    echo "  -T TYPE      Test type: simple, default, readonly"
    echo "  -j JOBS      Number of threads (default: 4)"
    echo "  -P PROGRESS  Progress interval in seconds (default: 30)"
    echo "  -r PROTOCOL  Query protocol: simple, extended (default: extended)"
    exit 1
}

# Defaults matching issue #63 methodology
CLIENTS=4
TIME=300
JOBS=4
PROGRESS=30
PROTOCOL=extended
PGUSER=${PGUSER:-postgres}
PGDATABASE=${PGDATABASE:-postgres}

while getopts "h:p:n:c:t:T:j:P:r:" opt; do
    case $opt in
        h) HOST=$OPTARG ;;
        p) PORT=$OPTARG ;;
        n) NAME=$OPTARG ;;
        c) CLIENTS=$OPTARG ;;
        t) TIME=$OPTARG ;;
        T) TYPE=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        P) PROGRESS=$OPTARG ;;
        r) PROTOCOL=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$HOST" ] || [ -z "$PORT" ] || [ -z "$NAME" ] || [ -z "$TYPE" ]; then
    usage
fi

# Build pgbench command based on test type
# Issue #63 uses: pgbench -T 300 -P 30 -r -c 4 -j 4 -S --protocol extended
case $TYPE in
    simple)
        # Simple SELECT 1 - measures pure proxy overhead
        PGBENCH_OPTS="-S"
        CUSTOM_SCRIPT=1
        ;;
    default)
        # Default TPC-B like workload
        PGBENCH_OPTS=""
        CUSTOM_SCRIPT=0
        ;;
    readonly)
        # Read-only workload (SELECT only) - primary test from issue #63
        PGBENCH_OPTS="-S"
        CUSTOM_SCRIPT=0
        ;;
    *)
        echo "Unknown test type: $TYPE"
        exit 1
        ;;
esac

# Add protocol option
PGBENCH_OPTS="$PGBENCH_OPTS --protocol $PROTOCOL"

# Create temp file for results
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE ${TMPFILE}.* 2>/dev/null" EXIT

# Run the actual benchmark
# Matches: pgbench -T 300 -P 30 -r -c 4 -j 4 -S --protocol extended postgres
echo "# Running ${TYPE} benchmark: ${NAME}" >&2
echo "# Command: pgbench -T $TIME -P $PROGRESS -r -c $CLIENTS -j $JOBS $PGBENCH_OPTS" >&2

if [ "$CUSTOM_SCRIPT" = "1" ]; then
    # Create custom script for SELECT 1
    SCRIPT_FILE=$(mktemp)
    echo "SELECT 1;" > "$SCRIPT_FILE"
    trap "rm -f $TMPFILE ${TMPFILE}.* $SCRIPT_FILE 2>/dev/null" EXIT

    pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
        -c "$CLIENTS" -j "$JOBS" -T "$TIME" -P "$PROGRESS" -r \
        --protocol "$PROTOCOL" -f "$SCRIPT_FILE" \
        2>&1 | tee "${TMPFILE}.out"
else
    pgbench -h "$HOST" -p "$PORT" -U "$PGUSER" -d "$PGDATABASE" \
        -c "$CLIENTS" -j "$JOBS" -T "$TIME" -P "$PROGRESS" -r \
        $PGBENCH_OPTS \
        2>&1 | tee "${TMPFILE}.out"
fi

# Parse and output results
OUTPUT="${TMPFILE}.out"

# Extract metrics from pgbench output
# Example output:
# tps = 10821.928070 (without initial connection time)
# latency average = 0.369 ms
# latency stddev = 0.099 ms
TPS=$(grep "tps = " "$OUTPUT" | grep -v "including" | tail -1 | sed 's/.*tps = \([0-9.]*\).*/\1/')
LATENCY_AVG=$(grep "latency average" "$OUTPUT" | sed 's/.*= \([0-9.]*\) ms.*/\1/')
LATENCY_STDDEV=$(grep "latency stddev" "$OUTPUT" | sed 's/.*= \([0-9.]*\) ms.*/\1/')

# Extract statement latency for the SELECT query
STMT_LATENCY=$(grep "SELECT" "$OUTPUT" | head -1 | awk '{print $1}')

# Output in CSV format
echo ""
echo "# Results (CSV format):"
echo "target,test_type,clients,tps,latency_avg_ms,latency_stddev_ms,stmt_latency_ms"
echo "${NAME},${TYPE},${CLIENTS},${TPS:-0},${LATENCY_AVG:-0},${LATENCY_STDDEV:-0},${STMT_LATENCY:-0}"

# Also output overhead calculation hint
echo ""
echo "# Latency: ${LATENCY_AVG:-0} ms (stddev: ${LATENCY_STDDEV:-0} ms)"
echo "# TPS: ${TPS:-0}"
