#!/usr/bin/env bats
#===============================================================================
# Unit Tests for vps-security.sh
#===============================================================================

# Setup - runs before each test
setup() {
    source "${BATS_TEST_DIRNAME}/../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../lib/helpers.sh"
    
    # Create temp directory for tests
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Mock functions that require root or external dependencies
    timedatectl() {
        case "$1" in
            "show")
                echo "Asia/Jakarta"
                ;;
            "set-timezone")
                echo "MOCK: Setting timezone to $2"
                return 0
                ;;
            "list-timezones")
                echo -e "Asia/Jakarta\nAsia/Makassar\nAsia/Jayapura\nUTC"
                ;;
        esac
    }
    export -f timedatectl
    
    # Mock apt-get
    apt-get() {
        echo "MOCK: apt-get $*"
        return 0
    }
    export -f apt-get
    
    # Mock ufw
    ufw() {
        echo "MOCK: ufw $*"
        return 0
    }
    export -f ufw
    
    # Mock systemctl
    systemctl() {
        echo "MOCK: systemctl $*"
        return 0
    }
    export -f systemctl
    
    # Mock fuser (for wait_for_apt)
    fuser() {
        return 1  # No lock held
    }
    export -f fuser
    
    # Now source the vps-security after mocks
    source "${BATS_TEST_DIRNAME}/../lib/vps-security.sh"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for timezone validation
#===============================================================================
@test "timezone: Asia/Jakarta is a valid timezone" {
    run timedatectl list-timezones
    [[ "$output" == *"Asia/Jakarta"* ]]
}

@test "timezone: UTC is a valid timezone" {
    run timedatectl list-timezones
    [[ "$output" == *"UTC"* ]]
}

#===============================================================================
# Tests for install_ufw function logic
#===============================================================================
@test "install_ufw: function exists" {
    run type install_ufw
    [ "$status" -eq 0 ]
}

@test "install_ufw: should call apt_install with ufw" {
    # Check function logic without actually installing
    run type install_ufw
    [[ "$output" == *"apt_install ufw"* ]]
}

#===============================================================================
# Tests for install_fail2ban function logic
#===============================================================================
@test "install_fail2ban: function exists" {
    run type install_fail2ban
    [ "$status" -eq 0 ]
}

@test "install_fail2ban: should call apt_install with fail2ban" {
    run type install_fail2ban
    [[ "$output" == *"apt_install fail2ban"* ]]
}

#===============================================================================
# Tests for update_packages function logic
#===============================================================================
@test "update_packages: function exists" {
    run type update_packages
    [ "$status" -eq 0 ]
}

@test "update_packages: should call apt-get update" {
    run type update_packages
    [[ "$output" == *"apt-get update"* ]]
}

@test "update_packages: should call apt-get dist-upgrade" {
    run type update_packages
    [[ "$output" == *"apt-get dist-upgrade"* ]]
}

@test "update_packages: should call apt-get autoremove" {
    run type update_packages
    [[ "$output" == *"apt-get autoremove"* ]]
}

#===============================================================================
# Tests for run_all_security function
#===============================================================================
@test "run_all_security: function exists" {
    run type run_all_security
    [ "$status" -eq 0 ]
}

@test "run_all_security: should call all security functions" {
    run type run_all_security
    [[ "$output" == *"setup_timezone"* ]]
    [[ "$output" == *"update_packages"* ]]
    [[ "$output" == *"install_ufw"* ]]
    [[ "$output" == *"install_fail2ban"* ]]
}
