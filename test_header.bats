#!/usr/bin/env bats

# Path to your script under test (edit as needed):
# If this test file is in the same folder as header.sh, do:
SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/header.sh"

# A setup function that runs before each test
setup() {
  # Create a temporary working directory for each test
  TEST_DIR="$(mktemp -d)"
  # Move into it
  cd "$TEST_DIR" || exit 1

  # Ensure script is executable
  if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
    chmod +x "$SCRIPT_UNDER_TEST"
  fi
}

# A teardown function that runs after each test
teardown() {
  # Remove the temporary directory
  rm -rf "$TEST_DIR"
}


###########################################
# HELPER FUNCTIONS
###########################################

# Check file contains a given pattern
function assert_file_contains() {
  local file="$1"
  local pattern="$2"
  run grep -Fq "$pattern" "$file"
  [ "$status" -eq 0 ]
}

###########################################
# TEST 1: Basic new file
###########################################
@test "Basic new file creation" {
  local file="hello.sh"

  run "$SCRIPT_UNDER_TEST" "$file"
  # Test that the script exited 0
  [ "$status" -eq 0 ]

  # Check that the file has a header with certain keywords
  assert_file_contains "$file" "Author:"
  assert_file_contains "$file" "Creation Date:"
  assert_file_contains "$file" "#!/bin/bash"
}

###########################################
# TEST 2: Prepend header to existing file
###########################################
@test "Prepend header to existing file" {
  local file="old.sh"
  echo "echo 'Hello World';" > "$file"

  run "$SCRIPT_UNDER_TEST" "$file"
  [ "$status" -eq 0 ]

  assert_file_contains "$file" "Author:"
  assert_file_contains "$file" "echo 'Hello World';"
}

###########################################
# TEST 3: Update version major -> 2.0.0
###########################################
@test "Update version: major" {
  local file="versioned.sh"
  echo "echo 'some code';" > "$file"

  # First create the header
  run "$SCRIPT_UNDER_TEST" "$file"
  [ "$status" -eq 0 ]

  # Now update major => from 1.0.0 to 2.0.0
  run "$SCRIPT_UNDER_TEST" --update major "$file"
  [ "$status" -eq 0 ]

  assert_file_contains "$file" "Version: 2.0.0"
}

###########################################
# TEST 4: Direct version update
###########################################
@test "Update version: direct (3.5.7)" {
  local file="direct_version.sh"
  echo "echo 'direct version';" > "$file"

  run "$SCRIPT_UNDER_TEST" "$file"
  [ "$status" -eq 0 ]

  run "$SCRIPT_UNDER_TEST" --update 3.5.7 "$file"
  [ "$status" -eq 0 ]

  assert_file_contains "$file" "Version: 3.5.7"
}

###########################################
# TEST 5: .header_config usage
###########################################
@test "Using .header_config" {
  local config=".header_config"
  local file="config_file.py"
  cat <<EOF > "$config"
Author=ConfigUser
Language=fr
Template=single
EOF

  run "$SCRIPT_UNDER_TEST" "$file"
  [ "$status" -eq 0 ]

  # We expect single-line style, French language
  assert_file_contains "$file" "[Auteur: ConfigUser"
    assert_file_contains "$file" "#!/usr/bin/env python"
}

###########################################
# TEST 6: CLI overrides .header_config
###########################################
@test "CLI overrides .header_config" {
  # .header_config is still present from previous test
  local file="override_test.py"

  run "$SCRIPT_UNDER_TEST" -l en -t default -s py -a CLIUser "$file"
  [ "$status" -eq 0 ]

    cat $file
  assert_file_contains "$file" "#!/usr/bin/env python"
  assert_file_contains "$file" "Author: CLIUser"
  assert_file_contains "$file" "Creation Date:"
  assert_file_contains "$file" "Version: 1.0.0"
}

###########################################
# TEST 7: Prompted description
###########################################
@test "Prompted description" {
  local file="desc_test.sh"

  # Provide "My test description" to the prompt
  # We run Bats "run" with a here-string for the script input
  run bash -c "echo 'My test description' | \"$SCRIPT_UNDER_TEST\" -d \"$file\""
  [ "$status" -eq 0 ]

  assert_file_contains "$file" "Description: My test description"
}

###########################################
# TEST 8: Invalid language
###########################################
@test "Invalid language fails" {
  run "$SCRIPT_UNDER_TEST" -l xyz invalid.sh
  # We expect a non-zero status
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Error: Invalid language" ]]
}

###########################################
# TEST 9: No file specified
###########################################
@test "No file specified" {
  run "$SCRIPT_UNDER_TEST" -c "#"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "No file specified" ]]
}
