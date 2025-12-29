#!/usr/bin/env bats
#===============================================================================
# Unit Tests for webserver.sh
#===============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../lib/helpers.sh"
    
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Mock external commands
    nginx() { echo "MOCK: nginx $*"; return 0; }
    export -f nginx
    
    php() { echo "PHP 8.3.0"; return 0; }
    export -f php
    
    mariadb() { echo "mariadb  Ver 15.1"; return 0; }
    export -f mariadb
    
    certbot() { echo "certbot 2.0.0"; return 0; }
    export -f certbot
    
    wp() { echo "WP-CLI 2.8.0"; return 0; }
    export -f wp
    
    curl() { echo "MOCK: curl $*"; cat > /dev/null; return 0; }
    export -f curl
    
    add-apt-repository() { echo "MOCK: add-apt-repository $*"; return 0; }
    export -f add-apt-repository
    
    apt-get() { echo "MOCK: apt-get $*"; return 0; }
    export -f apt-get
    
    systemctl() { echo "MOCK: systemctl $*"; return 0; }
    export -f systemctl
    
    fuser() { return 1; }
    export -f fuser
    
    mysql_secure_installation() { echo "MOCK: mysql_secure_installation"; return 0; }
    export -f mysql_secure_installation
    
    nproc() { echo "4"; }
    export -f nproc
    
    ulimit() { echo "1024"; }
    export -f ulimit
    
    source "${BATS_TEST_DIRNAME}/../lib/webserver.sh"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for PHP_VERSION variable
#===============================================================================
@test "PHP_VERSION: defaults to 8.3" {
    [ "$PHP_VERSION" = "8.3" ]
}

@test "PHP_VERSION: can be overridden" {
    PHP_VERSION="8.2"
    source "${BATS_TEST_DIRNAME}/../lib/webserver.sh"
    [ "$PHP_VERSION" = "8.2" ]
}

#===============================================================================
# Tests for install_nginx function
#===============================================================================
@test "install_nginx: function exists" {
    run type install_nginx
    [ "$status" -eq 0 ]
}

@test "install_nginx: uses ondrej/nginx PPA" {
    run type install_nginx
    [[ "$output" == *"ppa:ondrej/nginx"* ]]
}

#===============================================================================
# Tests for install_php function
#===============================================================================
@test "install_php: function exists" {
    run type install_php
    [ "$status" -eq 0 ]
}

@test "install_php: uses ondrej/php PPA" {
    run type install_php
    [[ "$output" == *"ppa:ondrej/php"* ]]
}

@test "install_php: installs required extensions" {
    run type install_php
    # Extensions use version suffix like php8.3-fpm
    [[ "$output" == *"-fpm"* ]]
    [[ "$output" == *"-mysql"* ]]
    [[ "$output" == *"-redis"* ]]
    [[ "$output" == *"-imagick"* ]]
}

#===============================================================================
# Tests for install_mariadb function
#===============================================================================
@test "install_mariadb: function exists" {
    run type install_mariadb
    [ "$status" -eq 0 ]
}

@test "install_mariadb: installs mariadb-server" {
    run type install_mariadb
    [[ "$output" == *"mariadb-server"* ]]
}

@test "install_mariadb: runs mysql_secure_installation" {
    run type install_mariadb
    [[ "$output" == *"mysql_secure_installation"* ]]
}

#===============================================================================
# Tests for install_certbot function
#===============================================================================
@test "install_certbot: function exists" {
    run type install_certbot
    [ "$status" -eq 0 ]
}

@test "install_certbot: installs nginx plugin" {
    run type install_certbot
    [[ "$output" == *"python3-certbot-nginx"* ]]
}

#===============================================================================
# Tests for install_wpcli function
#===============================================================================
@test "install_wpcli: function exists" {
    run type install_wpcli
    [ "$status" -eq 0 ]
}

@test "install_wpcli: downloads from correct URL" {
    run type install_wpcli
    [[ "$output" == *"wp-cli/builds/gh-pages/phar/wp-cli.phar"* ]]
}

@test "install_wpcli: moves to /usr/local/bin/wp" {
    run type install_wpcli
    [[ "$output" == *"/usr/local/bin/wp"* ]]
}

#===============================================================================
# Tests for configure_nginx function
#===============================================================================
@test "configure_nginx: function exists" {
    run type configure_nginx
    [ "$status" -eq 0 ]
}

#===============================================================================
# Tests for NGINX configuration content
#===============================================================================
@test "nginx config: uses worker_processes auto" {
    run type configure_nginx
    [[ "$output" == *"worker_processes auto"* ]]
}

@test "nginx config: sets keepalive_timeout 15" {
    run type configure_nginx
    [[ "$output" == *"keepalive_timeout 15"* ]]
}

@test "nginx config: enables gzip" {
    run type configure_nginx
    [[ "$output" == *"gzip on"* ]]
}

@test "nginx config: disables server_tokens" {
    run type configure_nginx
    [[ "$output" == *"server_tokens off"* ]]
}

@test "nginx config: uses modern TLS only (TLSv1.2 TLSv1.3)" {
    run type configure_nginx
    [[ "$output" == *"TLSv1.2 TLSv1.3"* ]]
}

@test "nginx config: sets client_max_body_size 64m" {
    run type configure_nginx
    [[ "$output" == *"client_max_body_size 64m"* ]]
}

#===============================================================================
# Tests for install_full_stack function
#===============================================================================
@test "install_full_stack: function exists" {
    run type install_full_stack
    [ "$status" -eq 0 ]
}

@test "install_full_stack: calls all installation functions" {
    run type install_full_stack
    [[ "$output" == *"install_nginx"* ]]
    [[ "$output" == *"install_php"* ]]
    [[ "$output" == *"install_mariadb"* ]]
    [[ "$output" == *"install_certbot"* ]]
    [[ "$output" == *"install_wpcli"* ]]
}
