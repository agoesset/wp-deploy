#!/usr/bin/env bats
#===============================================================================
# Unit Tests for Template Files
# Tests to validate template file content and potential issues
#===============================================================================

setup() {
    TEMPLATES_DIR="${BATS_TEST_DIRNAME}/../templates"
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for nginx.conf template
#===============================================================================
@test "nginx.conf: file exists" {
    [ -f "${TEMPLATES_DIR}/nginx.conf" ]
}

@test "nginx.conf: uses worker_processes auto" {
    grep -q "worker_processes auto" "${TEMPLATES_DIR}/nginx.conf"
}

@test "nginx.conf: has secure TLS settings (no TLSv1 or TLSv1.1)" {
    ! grep -q "TLSv1 " "${TEMPLATES_DIR}/nginx.conf"
    ! grep -q "TLSv1.1" "${TEMPLATES_DIR}/nginx.conf"
    grep -q "TLSv1.2 TLSv1.3" "${TEMPLATES_DIR}/nginx.conf"
}

@test "nginx.conf: disables server_tokens" {
    grep -q "server_tokens off" "${TEMPLATES_DIR}/nginx.conf"
}

@test "nginx.conf: has gzip enabled" {
    grep -q "gzip on" "${TEMPLATES_DIR}/nginx.conf"
}

@test "nginx.conf: sets client_max_body_size" {
    grep -q "client_max_body_size 64m" "${TEMPLATES_DIR}/nginx.conf"
}

#===============================================================================
# Tests for nginx-site.conf template
#===============================================================================
@test "nginx-site.conf: file exists" {
    [ -f "${TEMPLATES_DIR}/nginx-site.conf" ]
}

@test "nginx-site.conf: has HTTP to HTTPS redirect" {
    grep -q "return 301 https://" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: has http2 enabled" {
    grep -q "http2 on" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: blocks xmlrpc.php" {
    grep -q "location = /xmlrpc.php" "${TEMPLATES_DIR}/nginx-site.conf"
    grep -q "deny all" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: blocks wp-config.php" {
    grep -q "wp-config.php" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: has security headers" {
    grep -q "X-Frame-Options" "${TEMPLATES_DIR}/nginx-site.conf"
    grep -q "X-Content-Type-Options" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: uses placeholder {{DOMAIN}}" {
    grep -q "{{DOMAIN}}" "${TEMPLATES_DIR}/nginx-site.conf"
}

@test "nginx-site.conf: uses placeholder {{USER}}" {
    grep -q "{{USER}}" "${TEMPLATES_DIR}/nginx-site.conf"
}

#===============================================================================
# Tests for phpfpm-pool.conf template
#===============================================================================
@test "phpfpm-pool.conf: file exists" {
    [ -f "${TEMPLATES_DIR}/phpfpm-pool.conf" ]
}

@test "phpfpm-pool.conf: uses dynamic pm" {
    grep -q "pm = dynamic" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

@test "phpfpm-pool.conf: sets memory_limit" {
    grep -q "memory_limit" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

@test "phpfpm-pool.conf: sets upload_max_filesize" {
    grep -q "upload_max_filesize" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

@test "phpfpm-pool.conf: disables dangerous functions" {
    grep -q "disable_functions" "${TEMPLATES_DIR}/phpfpm-pool.conf"
    grep -q "exec" "${TEMPLATES_DIR}/phpfpm-pool.conf"
    grep -q "shell_exec" "${TEMPLATES_DIR}/phpfpm-pool.conf"
    grep -q "system" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

@test "phpfpm-pool.conf: uses unix socket" {
    grep -q "listen = /run/php/" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

@test "phpfpm-pool.conf: sets listen.owner to www-data" {
    grep -q "listen.owner = www-data" "${TEMPLATES_DIR}/phpfpm-pool.conf"
}

#===============================================================================
# Tests for wsc.conf template
#===============================================================================
@test "wsc.conf: file exists" {
    [ -f "${TEMPLATES_DIR}/wsc.conf" ]
}

@test "wsc.conf: excludes POST requests" {
    grep -q 'request_method = POST' "${TEMPLATES_DIR}/wsc.conf"
}

@test "wsc.conf: excludes logged in users" {
    grep -q "wordpress_logged_in" "${TEMPLATES_DIR}/wsc.conf"
}

@test "wsc.conf: has mobile detection" {
    grep -q "is_mobile" "${TEMPLATES_DIR}/wsc.conf"
    grep -q "iPhone" "${TEMPLATES_DIR}/wsc.conf"
    grep -q "Android" "${TEMPLATES_DIR}/wsc.conf"
}

@test "wsc.conf: uses supercache directory" {
    grep -q "wp-content/cache/supercache" "${TEMPLATES_DIR}/wsc.conf"
}

@test "wsc.conf: handles HTTPS cache files" {
    # wsc.conf uses variable pattern: ${cache_file}-https
    grep -q 'scheme = "https"' "${TEMPLATES_DIR}/wsc.conf"
}

#===============================================================================
# CRITICAL: Tests for potential duplicate location blocks
#===============================================================================
@test "wsc.conf: does NOT contain xmlrpc.php block (would conflict with nginx-site.conf)" {
    # wsc.conf should NOT have xmlrpc.php location block
    # because nginx-site.conf already has it, causing duplicate location error
    if grep -q "location = /xmlrpc.php" "${TEMPLATES_DIR}/wsc.conf"; then
        echo "ERROR: wsc.conf still contains xmlrpc.php location block"
        echo "This will cause 'duplicate location' error when included in nginx-site.conf"
        return 1
    else
        # Fixed - no duplicate
        return 0
    fi
}

@test "wsc.conf: count location blocks" {
    location_count=$(grep -c "location" "${TEMPLATES_DIR}/wsc.conf" || echo "0")
    echo "wsc.conf has $location_count location directives"
    [ "$location_count" -ge 1 ]
}

@test "nginx-site.conf: count xmlrpc.php blocks" {
    xmlrpc_count=$(grep -c "xmlrpc.php" "${TEMPLATES_DIR}/nginx-site.conf" || echo "0")
    echo "nginx-site.conf references xmlrpc.php $xmlrpc_count times"
    [ "$xmlrpc_count" -ge 1 ]
}
