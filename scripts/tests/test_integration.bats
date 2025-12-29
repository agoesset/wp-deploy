#!/usr/bin/env bats
#===============================================================================
# Integration Tests - Tests for potential issues across scripts
#===============================================================================

setup() {
    SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
    LIB_DIR="${SCRIPT_DIR}/lib"
    TEMPLATES_DIR="${SCRIPT_DIR}/templates"
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for script file existence and syntax
#===============================================================================
@test "main script exists" {
    [ -f "${SCRIPT_DIR}/vps-setup.sh" ]
}

@test "main script has valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/vps-setup.sh"
    [ "$status" -eq 0 ]
}

@test "colors.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/colors.sh"
    [ "$status" -eq 0 ]
}

@test "helpers.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/helpers.sh"
    [ "$status" -eq 0 ]
}

@test "vps-security.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/vps-security.sh"
    [ "$status" -eq 0 ]
}

@test "webserver.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/webserver.sh"
    [ "$status" -eq 0 ]
}

@test "wordpress.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/wordpress.sh"
    [ "$status" -eq 0 ]
}

@test "caching.sh has valid bash syntax" {
    run bash -n "${LIB_DIR}/caching.sh"
    [ "$status" -eq 0 ]
}

#===============================================================================
# CRITICAL: Duplicate location block detection
#===============================================================================
@test "no duplicate xmlrpc.php location when wsc.conf included" {
    # Verify that combining nginx-site.conf and wsc.conf won't cause duplicate location
    
    nginx_site="${TEMPLATES_DIR}/nginx-site.conf"
    wsc_conf="${TEMPLATES_DIR}/wsc.conf"
    
    # Count xmlrpc.php location blocks (tr removes newlines, || echo 0 handles no match)
    nginx_xmlrpc=$(grep -c "location = /xmlrpc.php" "$nginx_site" 2>/dev/null | tr -d '[:space:]')
    wsc_xmlrpc=$(grep -c "location = /xmlrpc.php" "$wsc_conf" 2>/dev/null | tr -d '[:space:]')
    
    # Default to 0 if empty
    nginx_xmlrpc=${nginx_xmlrpc:-0}
    wsc_xmlrpc=${wsc_xmlrpc:-0}
    
    total_xmlrpc=$((nginx_xmlrpc + wsc_xmlrpc))
    
    echo "nginx-site.conf has $nginx_xmlrpc xmlrpc location blocks"
    echo "wsc.conf has $wsc_xmlrpc xmlrpc location blocks"
    echo "Total when combined: $total_xmlrpc"
    
    # Verify no duplicate - total should be exactly 1 (only in nginx-site.conf)
    [ "$total_xmlrpc" -eq 1 ]
}

#===============================================================================
# Tests for PHP version consistency
#===============================================================================
@test "PHP version is consistent across scripts" {
    # Check that all scripts use the same PHP version variable
    php_refs_webserver=$(grep -c "PHP_VERSION" "${LIB_DIR}/webserver.sh" || echo "0")
    php_refs_wordpress=$(grep -c "PHP_VERSION" "${LIB_DIR}/wordpress.sh" || echo "0")
    php_refs_caching=$(grep -c "PHP_VERSION" "${LIB_DIR}/caching.sh" || echo "0")
    
    # All should reference PHP_VERSION variable
    [ "$php_refs_webserver" -gt 0 ]
    [ "$php_refs_wordpress" -gt 0 ]
    [ "$php_refs_caching" -gt 0 ]
}

@test "main script sets PHP_VERSION" {
    grep -q 'PHP_VERSION="8.3"' "${SCRIPT_DIR}/vps-setup.sh"
}

#===============================================================================
# Tests for required function dependencies
#===============================================================================
@test "all helper functions are defined" {
    source "${LIB_DIR}/colors.sh"
    source "${LIB_DIR}/helpers.sh"
    
    # Check required functions exist
    type check_root &>/dev/null
    type check_os &>/dev/null
    type check_command &>/dev/null
    type confirm &>/dev/null
    type input_prompt &>/dev/null
    type generate_password &>/dev/null
    type backup_file &>/dev/null
    type validate_domain &>/dev/null
    type sanitize_name &>/dev/null
}

#===============================================================================
# Tests for SSL URL consistency
#===============================================================================
@test "wordpress.sh uses HTTPS URL for WordPress installation" {
    grep -q 'site_url="https://' "${LIB_DIR}/wordpress.sh"
}

@test "nginx-site.conf redirects HTTP to HTTPS" {
    grep -q "return 301 https://" "${TEMPLATES_DIR}/nginx-site.conf"
}

#===============================================================================
# Tests for security configurations
#===============================================================================
@test "UFW allows SSH before enabling" {
    grep -q "ufw allow ssh" "${LIB_DIR}/vps-security.sh"
}

@test "nginx config blocks dotfiles" {
    grep -q 'location ~ /\\.' "${LIB_DIR}/wordpress.sh"
}

#===============================================================================
# Tests for database security
#===============================================================================
@test "database uses secure collation" {
    grep -q "utf8mb4_unicode_520_ci" "${LIB_DIR}/wordpress.sh"
}

@test "database user is localhost only" {
    grep -q "@'localhost'" "${LIB_DIR}/wordpress.sh"
}

#===============================================================================
# Tests for proper escaping in heredocs
#===============================================================================
@test "NGINX config properly escapes variables" {
    # In heredocs, $uri should be \$uri
    # Check that the escaping is correct
    grep -q '\$uri' "${LIB_DIR}/wordpress.sh"
}

#===============================================================================
# Tests for file permissions setup
#===============================================================================
@test "wordpress.sh runs commands as site user" {
    grep -q 'sudo -u "\$username"' "${LIB_DIR}/wordpress.sh"
}

@test "php-fpm pool sets correct socket ownership" {
    grep -q "listen.owner = www-data" "${TEMPLATES_DIR}/phpfpm-pool.conf"
    grep -q "listen.group = www-data" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}
