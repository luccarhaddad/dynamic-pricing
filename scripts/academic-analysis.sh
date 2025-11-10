#!/bin/bash
# academic-analysis.sh - Statistical Analysis of Fault Tolerance Experiments
#
# Runs each fault tolerance scenario multiple times and performs statistical analysis
# for academic research rigor (mean ± standard deviation, confidence intervals, etc.)
#
# Usage:
#   ./scripts/academic-analysis.sh [iterations] [scenarios]
#
# Examples:
#   ./scripts/academic-analysis.sh 10 all       # Run all scenarios 10 times each
#   ./scripts/academic-analysis.sh 5 "1 2 6"    # Run scenarios 1, 2, 6 five times each
#   ./scripts/academic-analysis.sh 3 2          # Run scenario 2 three times

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"
TEMP_DIR="$PROJECT_ROOT/academic-analysis-temp"
RESULTS_DIR="$PROJECT_ROOT/academic-analysis-results"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
ITERATIONS=${1:-10}
SCENARIOS=${2:-"1 2 3 4 5 6"}

# Parse scenarios
if [ "$SCENARIOS" = "all" ]; then
    SCENARIOS="1 2 3 4 5 6"
fi

#######################################
# Print header
#######################################
print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}║       ACADEMIC FAULT TOLERANCE STATISTICAL ANALYSIS           ║${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📊 Configuration:"
    echo "   • Iterations per scenario: $ITERATIONS"
    echo "   • Scenarios to test: $SCENARIOS"
    echo "   • Total test runs: $((ITERATIONS * $(echo $SCENARIOS | wc -w)))"
    echo "   • Estimated duration: $((ITERATIONS * $(echo $SCENARIOS | wc -w) * 2)) minutes"
    echo ""
}

#######################################
# Initialize directories
#######################################
init_directories() {
    echo -e "${YELLOW}[Setup]${NC} Initializing directories..."
    
    # Clean up any previous temp data
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Create CSV header
    echo "scenario,iteration,recovery_time_seconds,job_status,pods_recovered,checkpoint_used,timestamp" \
        > "$TEMP_DIR/raw_data.csv"
    
    echo -e "${GREEN}✓${NC} Directories ready"
}

#######################################
# Extract recovery time from test output
#######################################
extract_recovery_time() {
    local output=$1
    local scenario=$2
    
    # Extract recovery/failover time from console output
    local time=$(echo "$output" | grep -E "Recovery time:|Failover time:|Total recovery time:" | tail -1 | grep -oE "[0-9]+" | head -1)
    
    # If not found, return -1 (indicates failure or manual intervention)
    if [ -z "$time" ]; then
        echo "-1"
    else
        echo "$time"
    fi
}

#######################################
# Extract job status from test output
#######################################
extract_job_status() {
    local output=$1
    
    # Extract final job status
    local status=$(echo "$output" | grep "Job Status:" | tail -1 | grep -oE "RUNNING|FAILED|RESTARTING" | head -1)
    
    if [ -z "$status" ]; then
        echo "UNKNOWN"
    else
        echo "$status"
    fi
}

#######################################
# Run single test iteration
#######################################
run_iteration() {
    local scenario=$1
    local iteration=$2
    
    echo -e "${CYAN}  [Run $iteration/$ITERATIONS]${NC} Scenario $scenario..."
    
    # Run test and capture output
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$TEMP_DIR/s${scenario}_iter${iteration}_${timestamp}.log"
    
    # Run the test
    local start_time=$(date +%s)
    "$SCRIPT_DIR/k8s.sh" test-ft "$scenario" > "$output_file" 2>&1
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Extract metrics
    local recovery_time=$(extract_recovery_time "$(cat $output_file)" "$scenario")
    local job_status=$(extract_job_status "$(cat $output_file)")
    local pods_recovered=$(grep -c "condition met" "$output_file" || echo "0")
    local checkpoint_used=$(grep "Restored from checkpoint:" "$output_file" | grep -oE "[0-9]+" | head -1 || echo "N/A")
    
    # Record data
    echo "$scenario,$iteration,$recovery_time,$job_status,$pods_recovered,$checkpoint_used,$timestamp" \
        >> "$TEMP_DIR/raw_data.csv"
    
    # Brief output
    if [ "$recovery_time" != "-1" ]; then
        echo -e "     ${GREEN}✓${NC} Recovery: ${recovery_time}s, Status: $job_status"
    else
        echo -e "     ${YELLOW}⚠${NC} Manual intervention required, Status: $job_status"
    fi
    
    # Cooldown between iterations
    if [ "$iteration" -lt "$ITERATIONS" ]; then
        echo "     ⏳ Cooldown (30s)..."
        sleep 30
    fi
}

#######################################
# Calculate statistics for a scenario
#######################################
calculate_statistics() {
    local scenario=$1
    local scenario_name=$2
    
    echo -e "\n${YELLOW}[Analysis]${NC} Calculating statistics for Scenario $scenario..."
    
    # Extract recovery times for this scenario (excluding -1 which means FAILED)
    local times=$(awk -F',' -v s="$scenario" '$1==s && $3!="-1" {print $3}' "$TEMP_DIR/raw_data.csv")
    
    if [ -z "$times" ]; then
        echo -e "${RED}  ✗ No successful recoveries for scenario $scenario${NC}"
        echo "$scenario,$scenario_name,0,N/A,N/A,N/A,N/A,N/A,0" >> "$RESULTS_DIR/statistical_summary.csv"
        return
    fi
    
    # Count successful vs failed
    local total_runs=$ITERATIONS
    local successful=$(echo "$times" | wc -l | xargs)
    local failed=$((total_runs - successful))
    
    # Calculate statistics using Python (more accurate than bash)
    python3 - <<PYTHON_SCRIPT
import sys
import statistics

times = [float(x) for x in """$times""".split() if x.strip()]

if len(times) == 0:
    print("N/A,N/A,N/A,N/A,N/A")
    sys.exit(0)

mean = statistics.mean(times)
std_dev = statistics.stdev(times) if len(times) > 1 else 0
min_time = min(times)
max_time = max(times)
median = statistics.median(times)

# 95% confidence interval (assuming normal distribution)
# CI = mean ± (1.96 * std_dev / sqrt(n))
import math
n = len(times)
ci_margin = 1.96 * std_dev / math.sqrt(n) if n > 1 else 0

print(f"{mean:.2f},{std_dev:.2f},{min_time:.0f},{max_time:.0f},{median:.2f},{ci_margin:.2f}")
PYTHON_SCRIPT
    
    local stats_output=$(python3 - <<PYTHON_SCRIPT
import statistics
times = [float(x) for x in """$times""".split() if x.strip()]
if len(times) == 0:
    print("N/A,N/A,N/A,N/A,N/A,N/A")
else:
    mean = statistics.mean(times)
    std_dev = statistics.stdev(times) if len(times) > 1 else 0
    min_time = min(times)
    max_time = max(times)
    median = statistics.median(times)
    import math
    ci_margin = 1.96 * std_dev / math.sqrt(len(times)) if len(times) > 1 else 0
    print(f"{mean:.2f},{std_dev:.2f},{min_time:.0f},{max_time:.0f},{median:.2f},{ci_margin:.2f}")
PYTHON_SCRIPT
)
    
    # Parse stats
    IFS=',' read -r mean std_dev min_val max_val median ci_margin <<< "$stats_output"
    
    # Calculate success rate
    local success_rate=$(awk "BEGIN {printf \"%.1f\", ($successful / $total_runs) * 100}")
    
    # Save to summary
    echo "$scenario,$scenario_name,$successful,$mean,$std_dev,$min_val,$max_val,$median,$ci_margin,$success_rate" \
        >> "$RESULTS_DIR/statistical_summary.csv"
    
    # Display results
    echo -e "${GREEN}  ✓ Statistics calculated:${NC}"
    echo "     Mean: ${mean}s ± ${std_dev}s"
    echo "     95% CI: ${mean}s ± ${ci_margin}s"
    echo "     Range: [${min_val}s, ${max_val}s]"
    echo "     Median: ${median}s"
    echo "     Success rate: ${success_rate}% ($successful/$total_runs)"
}

#######################################
# Generate final report
#######################################
generate_report() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}║              STATISTICAL ANALYSIS COMPLETE                    ║${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    # Create summary report
    local report_file="$RESULTS_DIR/STATISTICAL_REPORT_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$report_file" << 'EOF_REPORT'
# Fault Tolerance Statistical Analysis Report

## Test Configuration

**Iterations:** ${ITERATIONS} runs per scenario
**Scenarios:** ${SCENARIOS}
**Date:** $(date +"%Y-%m-%d %H:%M:%S")

## Statistical Summary

| Scenario | Name | n | Mean (s) | Std Dev (s) | 95% CI (±) | Min (s) | Max (s) | Median (s) | Success % |
|----------|------|---|----------|-------------|------------|---------|---------|------------|-----------|
EOF_REPORT
    
    # Add data from CSV
    tail -n +2 "$RESULTS_DIR/statistical_summary.csv" | while IFS=',' read -r scenario name successful mean std min max median ci success_rate; do
        echo "| S$scenario | $name | $successful | $mean | $std | $ci | $min | $max | $median | $success_rate% |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF_REPORT

## Key Findings

### Recovery Time Distribution

EOF_REPORT
    
    # Calculate overall statistics (without pandas for simplicity)
    echo "" >> "$report_file"
    echo "### Overall Statistics" >> "$report_file"
    echo "" >> "$report_file"
    
    # Calculate using awk and Python (no pandas needed)
    awk -F',' 'NR>1 && $3>0 {
        sum+=$4; count++; 
        if(min=="" || $4<min) min=$4;
        if(max=="" || $4>max) max=$4;
    } 
    END {
        if(count>0) {
            printf "**Overall Mean Recovery Time:** %.2f seconds\n", sum/count
            printf "**Fastest Scenario:** %.0f seconds (min)\n", min
            printf "**Slowest Scenario:** %.0f seconds (max)\n", max
        }
    }' "$RESULTS_DIR/statistical_summary.csv" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "### Reproducibility Assessment" >> "$report_file"
    echo "" >> "$report_file"
    echo "| Scenario | Mean (s) | Std Dev (s) | CV (%) | Reproducibility |" >> "$report_file"
    echo "|----------|----------|-------------|--------|-----------------|" >> "$report_file"
    
    # Calculate CV% for each scenario
    awk -F',' 'NR>1 && $3>0 {
        cv = ($5 / $4) * 100
        if (cv < 10) repro = "Excellent (CV < 10%)"
        else if (cv < 20) repro = "Good (CV < 20%)"
        else if (cv < 30) repro = "Moderate (CV < 30%)"
        else repro = "Variable (CV ≥ 30%)"
        printf "| S%d | %.2f | %.2f | %.1f | %s |\n", $1, $4, $5, cv, repro
    }' "$RESULTS_DIR/statistical_summary.csv" >> "$report_file"
    
    cat >> "$report_file" << 'EOF_REPORT'

## Interpretation

### Statistical Significance

With n=${ITERATIONS} iterations per scenario, we can report results with confidence intervals at 95% level.

**Acceptable Variance:** Coefficient of Variation (CV) < 20% indicates reproducible behavior.

### Academic Reporting

For academic papers, report as:
```
Scenario X achieved mean recovery time of μ ± σ seconds (n=${ITERATIONS}, 95% CI: μ ± CI)
```

Example:
```
Scenario 2 (Active JobManager failure) demonstrated HA failover with mean recovery 
time of [MEAN] ± [STD] seconds (n=${ITERATIONS}, 95% CI: [MEAN] ± [CI]).
```

### Null Hypothesis Testing

**H₀:** Recovery times are consistent across runs (variance is not significant)
**H₁:** Recovery times vary significantly across runs

Use the Coefficient of Variation (CV) to assess:
- CV < 10%: Very consistent (H₀ accepted)
- CV 10-20%: Consistent (H₀ accepted with caution)
- CV > 20%: Variable (H₀ rejected, investigate causes)

## Raw Data

Complete raw data available in: `raw_data.csv`

## Recommendations

1. **For Publication:** Use mean ± 95% CI for reporting
2. **For SLAs:** Use max value as worst-case bound
3. **For Optimization:** Focus on scenarios with high std dev
4. **For Reproducibility:** Report CV% alongside recovery times

---

**Report Generated:** $(date +"%Y-%m-%d %H:%M:%S")
**Evidence Location:** fault-tolerance-evidence/
**Raw Data:** academic-analysis-results/raw_data.csv
**Summary:** academic-analysis-results/statistical_summary.csv
EOF_REPORT
    
    echo ""
    echo -e "${GREEN}📄 Report generated: $report_file${NC}"
    echo ""
    
    # Display summary table
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                    STATISTICAL SUMMARY${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Pretty print the summary table
    column -t -s',' "$RESULTS_DIR/statistical_summary.csv" | head -20
    
    echo ""
    echo -e "${GREEN}✓ Analysis complete!${NC}"
    echo ""
    echo "📁 Results saved to: $RESULTS_DIR/"
    echo "   • statistical_summary.csv - Aggregated statistics"
    echo "   • raw_data.csv - All individual run data"
    echo "   • STATISTICAL_REPORT_*.md - Full analysis report"
    echo ""
}

#######################################
# Run multiple iterations for a scenario
#######################################
run_scenario_iterations() {
    local scenario=$1
    local scenario_name=$2
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  SCENARIO $scenario: $scenario_name${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    for iter in $(seq 1 $ITERATIONS); do
        run_iteration "$scenario" "$iter"
    done
    
    echo ""
}

#######################################
# Get scenario name
#######################################
get_scenario_name() {
    case $1 in
        1) echo "Standby JobManager Failure" ;;
        2) echo "Active JobManager Failure (HA Failover)" ;;
        3) echo "Complete JobManager Failure" ;;
        4) echo "Single TaskManager Failure" ;;
        5) echo "Complete TaskManager Failure" ;;
        6) echo "Complete System Failure (Disaster Recovery)" ;;
        *) echo "Unknown Scenario" ;;
    esac
}

#######################################
# Main execution
#######################################
main() {
    print_header
    
    # Check prerequisites
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}✗ Python 3 is required for statistical analysis${NC}"
        echo "Install with: brew install python3 (macOS) or apt install python3 (Linux)"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl is required${NC}"
        exit 1
    fi
    
    # Confirm with user
    echo -e "${YELLOW}⚠  This will run $((ITERATIONS * $(echo $SCENARIOS | wc -w))) tests.${NC}"
    echo "   Estimated time: $((ITERATIONS * $(echo $SCENARIOS | wc -w) * 2)) minutes"
    echo ""
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    init_directories
    
    # Create summary CSV header
    echo "scenario,scenario_name,successful_runs,mean,std_dev,min,max,median,ci_95,success_rate" \
        > "$RESULTS_DIR/statistical_summary.csv"
    
    # Run each scenario
    for scenario in $SCENARIOS; do
        local scenario_name=$(get_scenario_name "$scenario")
        run_scenario_iterations "$scenario" "$scenario_name"
        calculate_statistics "$scenario" "$scenario_name"
    done
    
    # Copy raw data to results
    cp "$TEMP_DIR/raw_data.csv" "$RESULTS_DIR/raw_data.csv"
    
    # Generate final report
    generate_report
    
    # Clean up temp directory
    echo -e "${YELLOW}Cleaning up temporary data...${NC}"
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC} Temporary data cleaned"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                               ║${NC}"
    echo -e "${GREEN}║         🎓 STATISTICAL ANALYSIS COMPLETE 🎓                    ║${NC}"
    echo -e "${GREEN}║                                                               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps for your academic paper:"
    echo "  1. Review: $RESULTS_DIR/STATISTICAL_REPORT_*.md"
    echo "  2. Use mean ± 95% CI for reporting recovery times"
    echo "  3. Report CV% for reproducibility assessment"
    echo "  4. Include sample size (n=$ITERATIONS) in methodology"
    echo ""
    echo "Example paper statement:"
    echo '  "Scenario 2 achieved mean recovery time of [MEAN]±[CI]s (n='"$ITERATIONS"', CV=[CV]%)"'
    echo ""
}

# Run main function
main

