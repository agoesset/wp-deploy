#!/usr/bin/env bats
#===============================================================================
# Unit Tests for caching.sh
#===============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../lib/helpers.sh"
    
    TEST_TEMP_DIR=$(mktemp -d)
    export PHP_VERSION="8.3"
    
    # Mock external commands
    redis-server() { echo "Redis server v=7.0.0"; return 0; }
    export -f redis-server
    
    curl() { echo "MOCK"; return 0; }
    export -f curl
    
    gpg() { echo "MOCK: gpg $*"; return 0; }
    export -f gpg
    
    tee() { cat > /dev/null; return 0; }
    export -f tee
    
    apt-get() { echo "MOCK: apt-get $*"; return 0; }
    export -f apt-get
    
    nginx() { echo "MOCK: nginx $*"; return 0; }
    export -f nginx
    
    systemctl() { echo "MOCK: systemctl $*"; return 0; }
    export -f systemctl
    
    fuser() { return 1; }
    export -f fuser
    
    lsb_release() { echo "jammy"; }
    export -f lsb_release
    
    perl() { echo "MOCK: perl $*"; return 0; }
    export -f perl
    
    source "${BATS_TEST_DIRNAME}/../lib/caching.sh"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for install_redis function
#===============================================================================
@test "install_redis: function exists" {
    run type install_redis
    [ "$status" -eq 0 ]
}

@test "install_redis: adds Redis official repository" {
    run type install_redis
    [[ "$output" == *"packages.redis.io"* ]]
}

@test "install_redis: installs redis-server package" {
    run type install_redis
    [[ "$output" == *"redis-server"* ]]
}

@test "install_redis: enables redis-server service" {
    run type install_redis
    [[ "$output" == *"systemctl enable redis-server"* ]]
}

@test "install_redis: restarts PHP-FPM after installation" {
    run type install_redis
    # Check for PHP-FPM restart pattern (variable interpolation)
    [[ "$output" == *"-fpm"* ]]
}

#===============================================================================
# Tests for configure_wsc_nginx function
#===============================================================================
@test "configure_wsc_nginx: function exists" {
    run type configure_wsc_nginx
    [ "$status" -eq 0 ]
}

@test "configure_wsc_nginx: creates /etc/nginx/inc directory" {
    run type configure_wsc_nginx
    [[ "$output" == *"/etc/nginx/inc"* ]]
}

@test "configure_wsc_nginx: creates wsc.conf file" {
    run type configure_wsc_nginx
    [[ "$output" == *"wsc.conf"* ]]
}

#===============================================================================
# Tests for WSC Configuration Content
#===============================================================================
@test "wsc config: sets cache_uri variable" {
    run type configure_wsc_nginx
    [[ "$output" == *'$cache_uri'* ]]
}

@test "wsc config: excludes POST requests from cache" {
    run type configure_wsc_nginx
    [[ "$output" == *'$request_method = POST'* ]]
}

@test "wsc config: excludes logged in users from cache" {
    run type configure_wsc_nginx
    [[ "$output" == *"wordpress_logged_in"* ]]
}

@test "wsc config: handles mobile detection" {
    run type configure_wsc_nginx
    [[ "$output" == *"is_mobile"* ]]
}

@test "wsc config: uses supercache path" {
    run type configure_wsc_nginx
    [[ "$output" == *"wp-content/cache/supercache"* ]]
}

@test "wsc config: excludes wp-admin from cache" {
    run type configure_wsc_nginx
    [[ "$output" == *"wp-admin"* ]]
}

@test "wsc config: excludes wp-login from cache" {
    run type configure_wsc_nginx
    # wp-login is part of the wp-(app|cron|login|register|mail).php pattern
    [[ "$output" == *"wp-"* ]] && [[ "$output" == *"login"* ]]
}

#===============================================================================
# Tests for install_all_caching function
#===============================================================================
@test "install_all_caching: function exists" {
    run type install_all_caching
    [ "$status" -eq 0 ]
}

@test "install_all_caching: calls install_redis" {
    run type install_all_caching
    [[ "$output" == *"install_redis"* ]]
}
