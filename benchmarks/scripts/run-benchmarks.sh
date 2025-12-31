#!/bin/bash
# Main benchmark runner script
# Based on methodology from:
# https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/63

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
source "${BENCH_DIR}/config/benchmark.env"

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="${BENCH_DIR}/results/${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# Results file
RESULTS_FILE="${RESULTS_DIR}/results.csv"
echo "target,test_type,clients,tps,latency_avg_ms,latency_stddev_ms,stmt_latency_ms,run" > "$RESULTS_FILE"

# Log file
LOG_FILE="${RESULTS_DIR}/benchmark.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_endpoint() {
    local target=$1
    case $target in
        postgres)
            echo "${POSTGRES_HOST}:${POSTGRES_PORT}"
            ;;
        pgbouncer)
            echo "${PGBOUNCER_HOST}:${PGBOUNCER_PORT}"
            ;;
        multigres)
            echo "${MULTIGRES_HOST}:${MULTIGRES_PORT}"
            ;;
        pgdog)
            echo "${PGDOG_HOST:-localhost}:${PGDOG_PORT:-6433}"
            ;;
        spqr)
            echo "${SPQR_HOST:-localhost}:${SPQR_PORT:-6435}"
            ;;
        citus)
            echo "${CITUS_HOST:-localhost}:${CITUS_PORT:-6434}"
            ;;
        *)
            echo "localhost:5432"
            ;;
    esac
}

check_target() {
    local target=$1
    local endpoint=$(get_endpoint "$target")
    local host=${endpoint%:*}
    local port=${endpoint#*:}

    if pg_isready -h "$host" -p "$port" -U postgres -q 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

run_benchmark() {
    local target=$1
    local test_type=$2
    local clients=$3
    local run_num=$4

    local endpoint=$(get_endpoint "$target")
    local host=${endpoint%:*}
    local port=${endpoint#*:}

    log "Running: ${target} / ${test_type} / ${clients} clients (run ${run_num}/${REPEATS})"

    # Run single benchmark and capture output
    local output
    output=$("${SCRIPT_DIR}/run-single-bench.sh" \
        -h "$host" \
        -p "$port" \
        -n "$target" \
        -c "$clients" \
        -t "$PGBENCH_TIME" \
        -T "$test_type" \
        -j "$PGBENCH_JOBS" \
        -P "$PGBENCH_PROGRESS" \
        -r "$PGBENCH_PROTOCOL" 2>&1)

    # Extract CSV line and append run number
    local csv_line
    csv_line=$(echo "$output" | grep "^${target}," | head -1)

    if [ -n "$csv_line" ]; then
        echo "${csv_line},${run_num}" >> "$RESULTS_FILE"
        local tps=$(echo "$csv_line" | cut -d',' -f4)
        local lat=$(echo "$csv_line" | cut -d',' -f5)
        log "  TPS: ${tps}, Latency: ${lat} ms"
    else
        log "  WARNING: No results captured"
    fi

    # Save full output
    echo "$output" >> "${RESULTS_DIR}/${target}_${test_type}_${clients}_run${run_num}.log"
}

# Print banner
echo "=============================================="
echo "PostgreSQL Proxy Latency Benchmark"
echo "Based on: gitlab.com/postgres-ai/.../issues/63"
echo "=============================================="
echo ""
log "Starting benchmark run: ${TIMESTAMP}"
log "Configuration:"
log "  Scale factor: ${PGBENCH_SCALE}"
log "  Test duration: ${PGBENCH_TIME}s"
log "  Progress interval: ${PGBENCH_PROGRESS}s"
log "  Protocol: ${PGBENCH_PROTOCOL}"
log "  Repeats: ${REPEATS}"
log "  Client counts: ${PGBENCH_CLIENTS}"
log "  Test types: ${TEST_TYPES}"
log "  Targets: ${TARGETS}"
log ""

# Check which targets are available
AVAILABLE_TARGETS=""
for target in $TARGETS; do
    if check_target "$target"; then
        AVAILABLE_TARGETS="$AVAILABLE_TARGETS $target"
        log "Target available: ${target} ($(get_endpoint "$target"))"
    else
        log "Target NOT available: ${target} ($(get_endpoint "$target")) - skipping"
    fi
done

if [ -z "$AVAILABLE_TARGETS" ]; then
    log "ERROR: No targets available. Start services first."
    exit 1
fi

log ""
log "Running benchmarks..."
log ""

# Run all benchmark combinations
total_tests=0
for target in $AVAILABLE_TARGETS; do
    for test_type in $TEST_TYPES; do
        for clients in $PGBENCH_CLIENTS; do
            for run in $(seq 1 "$REPEATS"); do
                total_tests=$((total_tests + 1))
            done
        done
    done
done

current_test=0
for target in $AVAILABLE_TARGETS; do
    for test_type in $TEST_TYPES; do
        for clients in $PGBENCH_CLIENTS; do
            for run in $(seq 1 "$REPEATS"); do
                current_test=$((current_test + 1))
                log "Progress: ${current_test}/${total_tests}"
                run_benchmark "$target" "$test_type" "$clients" "$run"

                # Brief pause between tests
                sleep 2
            done
        done
    done
done

log ""
log "Benchmark run complete!"
log "Results saved to: ${RESULTS_DIR}"
log ""

# Generate summary
"${SCRIPT_DIR}/analyze-results.sh" "${RESULTS_FILE}" | tee "${RESULTS_DIR}/summary.txt"

echo ""
echo "Full results: ${RESULTS_FILE}"
echo "Summary: ${RESULTS_DIR}/summary.txt"
