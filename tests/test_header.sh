#!/usr/bin/env bash
# --------------------------------------------------------------------------
# test_header.sh
#
# A classic shell-based test suite for header.sh, without using Bats.
# It runs a series of tests to verify header insertion, updates, and error handling.
#
# This test script has been generated from an bats testing script:
#
# --------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# --------------------------
# VARIABLES & COUNTERS
# --------------------------
SCRIPT_UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/header.sh"
# Total number of tests executed
TOTAL=0
# Number of passed tests
PASSED=0
# Number of failed tests
FAILED=0

# --------------------------
# HELPER FUNCTIONS
# --------------------------

# assert_file_contains <file> <pattern>
# Checks if <file> contains <pattern>, increments counters accordingly
assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq "$pattern" "$file"; then
    return 0
  else
    return 1
  fi
}

# run_test <name> <command>
# Executes a test command, captures failures, and updates counters
run_test() {
  local name="$1"
  shift
  TOTAL=$((TOTAL+1))
  echo "Running test: $name..."

  # Use a subshell to contain side effects like cd
  if ("$@"); then
    echo "✔ PASS: $name"
    PASSED=$((PASSED+1))
  else
    echo "✖ FAIL: $name"
    FAILED=$((FAILED+1))
  fi
  echo
}

# --------------------------
# TESTS
# --------------------------

test_basic_new_file() {
  # Create isolated directory and switch into it
  TEST_DIR=$(mktemp -d)  # mktemp -d creates a unique temporary directory
  (cd "$TEST_DIR" && \
    # Ensure our script is executable
    chmod +x "$SCRIPT_UNDER_TEST" && \
    # Run the script to create a new file
    "$SCRIPT_UNDER_TEST" "hello.sh" && \
    # Assertions: check for key header lines
    assert_file_contains "hello.sh" "Author:" && \
    assert_file_contains "hello.sh" "Creation Date:" && \
    assert_file_contains "hello.sh" "#!/bin/bash"
  )
  rm -rf "$TEST_DIR"
}

test_prepend_header_existing() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    echo "echo 'Hello World'" > old.sh && \
    chmod +x "$SCRIPT_UNDER_TEST" && \
    "$SCRIPT_UNDER_TEST" "old.sh" && \
    assert_file_contains "old.sh" "Author:" && \
    assert_file_contains "old.sh" "echo 'Hello World'"
  )
  rm -rf "$TEST_DIR"
}

test_update_version_major() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    echo "echo 'code'" > versioned.sh && \
    chmod +x "$SCRIPT_UNDER_TEST" && \
    # Initialize header to set version to 1.0.0
    "$SCRIPT_UNDER_TEST" "versioned.sh" && \
    # Update major version
    "$SCRIPT_UNDER_TEST" --update major "versioned.sh" && \
    assert_file_contains "versioned.sh" "Version: 2.0.0"
  )
  rm -rf "$TEST_DIR"
}

test_update_version_direct() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    echo "echo 'direct'" > direct_version.sh && \
    chmod +x "$SCRIPT_UNDER_TEST" && \
    "$SCRIPT_UNDER_TEST" "direct_version.sh" && \
    "$SCRIPT_UNDER_TEST" --update 3.5.7 "direct_version.sh" && \
    assert_file_contains "direct_version.sh" "Version: 3.5.7"
  )
  rm -rf "$TEST_DIR"
}

test_header_config_usage() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    # Create config file with custom values
    cat <<EOF > .header_config
Author=ConfigUser
Language=fr
Template=single
EOF
    echo "print('hi')" > config_file.py && \
    chmod +x "$SCRIPT_UNDER_TEST" && \
    "$SCRIPT_UNDER_TEST" "config_file.py" && \
    # In French, Author key is "Auteur"
    assert_file_contains "config_file.py" "Auteur:" && \
    # Shebang for Python
    assert_file_contains "config_file.py" "#!/usr/bin/env python"
  )
  rm -rf "$TEST_DIR"
}

test_cli_overrides_config() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    # Run with explicit CLI flags
    chmod +x "$SCRIPT_UNDER_TEST" && \
    "$SCRIPT_UNDER_TEST" -l en -t default -s py -a CLIUser "override_test.py" && \
    assert_file_contains "override_test.py" "#!/usr/bin/env python" && \
    assert_file_contains "override_test.py" "Author: CLIUser" && \
    assert_file_contains "override_test.py" "Version: 1.0.0"
  )
  rm -rf "$TEST_DIR"
}

test_prompted_description() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    # Pipe description into the script
    printf "My test description\n" | bash -c "${SCRIPT_UNDER_TEST} -d desc_test.sh" && \
    assert_file_contains "desc_test.sh" "Description: My test description"
  )
  rm -rf "$TEST_DIR"
}

test_invalid_language() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    # Capture stdout+stderr and exit code
    set +e && \
    output=$("$SCRIPT_UNDER_TEST" -l xyz invalid.sh 2>&1); status=$? && \
    set -e && \
    # Expect non-zero status and error message
    [ "$status" -ne 0 ] && [[ "$output" =~ "Error: Invalid language" ]]
  )
  rm -rf "$TEST_DIR"
}

test_no_file_specified() {
  TEST_DIR=$(mktemp -d)
  (cd "$TEST_DIR" && \
    set +e && \
    output=$("$SCRIPT_UNDER_TEST" -c "#" 2>&1); status=$? && \
    set -e && \
    [ "$status" -ne 0 ] && [[ "$output" =~ "Error: No file specified" ]]
  )
  rm -rf "$TEST_DIR"
}

# --------------------------
# RUN ALL TESTS
# --------------------------

echo "Starting test suite..."

run_test "Basic new file creation" test_basic_new_file
run_test "Prepend header to existing file" test_prepend_header_existing
run_test "Update version: major" test_update_version_major
run_test "Update version: direct (3.5.7)" test_update_version_direct
run_test "Using .header_config" test_header_config_usage
run_test "CLI overrides .header_config" test_cli_overrides_config
run_test "Prompted description" test_prompted_description
run_test "Invalid language fails" test_invalid_language
run_test "No file specified" test_no_file_specified

# --------------------------
# SUMMARY
# --------------------------

echo "Test summary: $PASSED/$TOTAL passed, $FAILED failed."
if [ "$FAILED" -ne 0 ]; then
  exit 1  # Non-zero exit if any test failed
else
  echo "All tests passed!"
  exit 0
fi
