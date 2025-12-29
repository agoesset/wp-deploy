#!/usr/bin/env bats
#===============================================================================
# Unit Tests for helpers.sh
#===============================================================================

# Setup - runs before each test
setup() {
    # Load the colors first (required for helpers)
    source "${BATS_TEST_DIRNAME}/../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../lib/helpers.sh"
    
    # Create temp directory for tests
    TEST_TEMP_DIR=$(mktemp -d)
}

# Teardown - runs after each test
teardown() {
    # Cleanup temp directory
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for check_command
#===============================================================================
@test "check_command: returns 0 for existing command (bash)" {
    run check_command bash
    [ "$status" -eq 0 ]
}

@test "check_command: returns 1 for non-existing command" {
    run check_command nonexistent_command_xyz123
    [ "$status" -eq 1 ]
}

@test "check_command: returns 0 for ls command" {
    run check_command ls
    [ "$status" -eq 0 ]
}

#===============================================================================
# Tests for generate_password
#===============================================================================
@test "generate_password: generates password with default length 16" {
    result=$(generate_password)
    [ ${#result} -eq 16 ]
}

@test "generate_password: generates password with custom length 24" {
    result=$(generate_password 24)
    [ ${#result} -eq 24 ]
}

@test "generate_password: generates password with custom length 8" {
    result=$(generate_password 8)
    [ ${#result} -eq 8 ]
}

@test "generate_password: generates different passwords each time" {
    pass1=$(generate_password)
    pass2=$(generate_password)
    [ "$pass1" != "$pass2" ]
}

#===============================================================================
# Tests for generate_random_string
#===============================================================================
@test "generate_random_string: generates string with default length 12" {
    result=$(generate_random_string)
    [ ${#result} -eq 12 ]
}

@test "generate_random_string: generates alphanumeric only" {
    result=$(generate_random_string 100)
    # Should only contain A-Za-z0-9
    [[ "$result" =~ ^[A-Za-z0-9]+$ ]]
}

#===============================================================================
# Tests for sanitize_name
#===============================================================================
@test "sanitize_name: replaces dots with underscores" {
    result=$(sanitize_name "example.com")
    [ "$result" = "example_com" ]
}

@test "sanitize_name: replaces dashes with underscores" {
    result=$(sanitize_name "my-site")
    [ "$result" = "my_site" ]
}

@test "sanitize_name: converts to lowercase" {
    result=$(sanitize_name "MyDomain.COM")
    [ "$result" = "mydomain_com" ]
}

@test "sanitize_name: removes special characters" {
    result=$(sanitize_name "test@domain#123")
    [ "$result" = "testdomain123" ]
}

@test "sanitize_name: handles complex domain" {
    result=$(sanitize_name "my-awesome.site.co.id")
    [ "$result" = "my_awesome_site_co_id" ]
}

#===============================================================================
# Tests for validate_domain
#===============================================================================
@test "validate_domain: accepts valid domain example.com" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts subdomain www.example.com" {
    run validate_domain "www.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts domain with dash my-site.com" {
    run validate_domain "my-site.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts .co.id domain" {
    run validate_domain "mitra.web.id"
    [ "$status" -eq 0 ]
}

@test "validate_domain: rejects domain without TLD" {
    run validate_domain "example"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain with underscore" {
    run validate_domain "my_site.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain starting with dash" {
    run validate_domain "-example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects empty string" {
    run validate_domain ""
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects IP address format" {
    run validate_domain "192.168.1.1"
    [ "$status" -eq 1 ]
}

#===============================================================================
# Tests for backup_file
#===============================================================================
@test "backup_file: creates backup of existing file" {
    # Create test file
    echo "test content" > "${TEST_TEMP_DIR}/testfile.txt"
    
    backup_file "${TEST_TEMP_DIR}/testfile.txt"
    
    # Check backup was created (pattern: testfile.txt.bak.*)
    backup_count=$(ls "${TEST_TEMP_DIR}"/testfile.txt.bak.* 2>/dev/null | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "backup_file: backup contains same content as original" {
    echo "original content here" > "${TEST_TEMP_DIR}/original.txt"
    
    backup_file "${TEST_TEMP_DIR}/original.txt"
    
    backup_file=$(ls "${TEST_TEMP_DIR}"/original.txt.bak.* | head -1)
    original_content=$(cat "${TEST_TEMP_DIR}/original.txt")
    backup_content=$(cat "$backup_file")
    
    [ "$original_content" = "$backup_content" ]
}

@test "backup_file: does nothing for non-existing file" {
    run backup_file "${TEST_TEMP_DIR}/nonexistent.txt"
    [ "$status" -eq 0 ]
    
    backup_count=$(ls "${TEST_TEMP_DIR}"/nonexistent.txt.bak.* 2>/dev/null | wc -l)
    [ "$backup_count" -eq 0 ]
}

#===============================================================================
# Tests for ensure_dir
#===============================================================================
@test "ensure_dir: creates directory if not exists" {
    ensure_dir "${TEST_TEMP_DIR}/newdir"
    [ -d "${TEST_TEMP_DIR}/newdir" ]
}

@test "ensure_dir: does not fail if directory already exists" {
    mkdir -p "${TEST_TEMP_DIR}/existingdir"
    run ensure_dir "${TEST_TEMP_DIR}/existingdir"
    [ "$status" -eq 0 ]
}

@test "ensure_dir: creates nested directories" {
    ensure_dir "${TEST_TEMP_DIR}/a/b/c/d"
    [ -d "${TEST_TEMP_DIR}/a/b/c/d" ]
}
