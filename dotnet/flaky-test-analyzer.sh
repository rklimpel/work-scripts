#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <Number_of_runs>"
  exit 1
fi

RUNS=$1
TEMP_FILE=$(mktemp)
TOTAL_DURATION=0
TOTAL_TESTS_EXECUTED=0

echo "Starting $RUNS test runs..."

for i in $(seq 1 "$RUNS"); do
  START_TIME=$(date +%s)
  
  # Runs the tests and captures the output (without building)
  TEST_OUTPUT=$(dotnet test --no-build)
  
  # Filters failures and appends them to the temp file
  echo "$TEST_OUTPUT" | grep -E "^\s*Failed\s" | awk '{print $2}' >> "$TEMP_FILE"
  
  # Extracts the total number of tests in this run (summed across all test projects)
  RUN_TOTAL=$(echo "$TEST_OUTPUT" | grep "Total:" | awk -F'Total:[[:space:]]*' '{print $2}' | awk -F',' '{print $1}' | awk '{s+=$1} END {print s}')
  
  # Fallback if awk finds nothing
  if [ -z "$RUN_TOTAL" ]; then RUN_TOTAL=0; fi
  
  TOTAL_TESTS_EXECUTED=$((TOTAL_TESTS_EXECUTED + RUN_TOTAL))
  
  END_TIME=$(date +%s)
  
  # Calculate times
  LAST_DURATION=$((END_TIME - START_TIME))
  TOTAL_DURATION=$((TOTAL_DURATION + LAST_DURATION))
  
  # Average duration for more precise ETA
  AVG_DURATION=$((TOTAL_DURATION / i))
  REMAINING_RUNS=$((RUNS - i))
  REMAINING_SECONDS=$((AVG_DURATION * REMAINING_RUNS))
  
  # Format remaining time (MM:SS)
  REMAINING_FORMATTED=$(printf "%02d:%02d" $((REMAINING_SECONDS / 60)) $((REMAINING_SECONDS % 60)))
  
  # Calculate estimated completion time (Format: HH:MM:SS)
  if date --version >/dev/null 2>&1; then
    ETA=$(date -d "+$REMAINING_SECONDS seconds" "+%H:%M:%S")
  else
    ETA=$(date -r $(( $(date +%s) + REMAINING_SECONDS )) "+%H:%M:%S")
  fi
  
  echo "Run $i/$RUNS completed. Duration: ${LAST_DURATION}s | Tests: $RUN_TOTAL | Estimated remaining time: $REMAINING_FORMATTED | ETA: $ETA"
done

echo ""
echo "========================================="
echo "Statistics & Flaky Tests"
echo "========================================="

# Format total duration in HH:MM:SS
TOTAL_DURATION_FORMATTED=$(printf "%02d:%02d:%02d" $((TOTAL_DURATION / 3600)) $(((TOTAL_DURATION % 3600) / 60)) $((TOTAL_DURATION % 60)))

# Evaluate test cases
TOTAL_FAILURES=$(wc -l < "$TEMP_FILE" | awk '{print $1}')
UNIQUE_FLAKY_TESTS=$(sort "$TEMP_FILE" | uniq | wc -l | awk '{print $1}')

echo "Total runs:              $RUNS"
echo "Total duration:          $TOTAL_DURATION_FORMATTED (HH:MM:SS)"
echo "Total test executions:   $TOTAL_TESTS_EXECUTED"

if [ "$TOTAL_TESTS_EXECUTED" -gt 0 ]; then
  FAILURE_RATE_GLOBAL=$(awk "BEGIN {printf \"%.4f\", ($TOTAL_FAILURES / $TOTAL_TESTS_EXECUTED) * 100}")
  echo "Failed tests:            $TOTAL_FAILURES ($FAILURE_RATE_GLOBAL% of total executions)"
fi

echo "Unique flaky tests:      $UNIQUE_FLAKY_TESTS"
echo "========================================="

if [ -s "$TEMP_FILE" ]; then
  echo "Breakdown of flaky tests:"
  # Sorts, counts and calculates the flake rate per testcase
  sort "$TEMP_FILE" | uniq -c | sort -nr | while read -r count testcase; do
    FLAKE_RATE_PER_RUN=$(awk "BEGIN {printf \"%.1f\", ($count / $RUNS) * 100}")
    echo "- $testcase"
    echo "  -> Failed in $count/$RUNS runs ($FLAKE_RATE_PER_RUN%)"
  done
else
  echo "All tests passed successfully in $RUNS runs."
fi

rm "$TEMP_FILE"