#!/usr/bin/env bats
#===============================================================================
# Unit Tests for wordpress.sh
#===============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../lib/helpers.sh"
    
    TEST_TEMP_DIR=$(mktemp -d)
    export PHP_VERSION="8.3"
    
    # Mock external commands
    useradd() { echo "MOCK: useradd $*"; return 0; }
    export -f useradd
    
    usermod() { echo "MOCK: usermod $*"; return 0; }
    export -f usermod
    
    id() { return 1; }  # User doesn't exist by default
    export -f id
    
    chown() { echo "MOCK: chown $*"; return 0; }
    export -f chown
    
    nginx() { echo "MOCK: nginx $*"; return 0; }
    export -f nginx
    
    php-fpm8.3() { return 0; }
    export -f php-fpm8.3
    
    certbot() { echo "MOCK: certbot $*"; return 0; }
    export -f certbot
    
    mariadb() { 
        if [[ "$*" == *"-p"* ]]; then
            cat > /dev/null  # consume stdin
        fi
        return 0
    }
    export -f mariadb
    
    wp() { echo "MOCK: wp $*"; return 0; }
    export -f wp
    
    sudo() { 
        shift  # remove -u
        shift  # remove username
        "$@"
        return 0
    }
    export -f sudo
    
    curl() { echo "1.2.3.4"; return 0; }
    export -f curl
    
    crontab() { echo "MOCK: crontab $*"; return 0; }
    export -f crontab
    
    systemctl() { echo "MOCK: systemctl $*"; return 0; }
    export -f systemctl
    
    fuser() { return 1; }
    export -f fuser
    
    source "${BATS_TEST_DIRNAME}/../lib/wordpress.sh"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Tests for create_site_user function
#===============================================================================
@test "create_site_user: function exists" {
    run type create_site_user
    [ "$status" -eq 0 ]
}

@test "create_site_user: uses useradd command" {
    run type create_site_user
    [[ "$output" == *"useradd"* ]]
}

@test "create_site_user: adds www-data to user group" {
    run type create_site_user
    [[ "$output" == *"usermod -a -G"* ]]
    [[ "$output" == *"www-data"* ]]
}

#===============================================================================
# Tests for create_site_folders function
#===============================================================================
@test "create_site_folders: function exists" {
    run type create_site_folders
    [ "$status" -eq 0 ]
}

@test "create_site_folders: creates public directory" {
    run type create_site_folders
    [[ "$output" == *"/public"* ]]
}

@test "create_site_folders: creates logs directory" {
    run type create_site_folders
    [[ "$output" == *"/logs"* ]]
}

#===============================================================================
# Tests for create_phpfpm_pool function
#===============================================================================
@test "create_phpfpm_pool: function exists" {
    run type create_phpfpm_pool
    [ "$status" -eq 0 ]
}

@test "create_phpfpm_pool: creates pool config in correct path" {
    run type create_phpfpm_pool
    # Check for the pool.d path pattern
    [[ "$output" == *"/etc/php/"* ]] && [[ "$output" == *"/fpm/pool.d/"* ]]
}

@test "create_phpfpm_pool: sets pm = dynamic" {
    run type create_phpfpm_pool
    [[ "$output" == *"pm = dynamic"* ]]
}

@test "create_phpfpm_pool: sets memory_limit = 256M" {
    run type create_phpfpm_pool
    [[ "$output" == *"memory_limit] = 256M"* ]]
}

@test "create_phpfpm_pool: disables dangerous functions" {
    run type create_phpfpm_pool
    [[ "$output" == *"exec,passthru,shell_exec,system"* ]]
}

@test "create_phpfpm_pool: creates socket in /run/php/" {
    run type create_phpfpm_pool
    [[ "$output" == *"listen = /run/php/php-"* ]]
}

#===============================================================================
# Tests for create_nginx_config function
#===============================================================================
@test "create_nginx_config: function exists" {
    run type create_nginx_config
    [ "$status" -eq 0 ]
}

@test "create_nginx_config: creates config in sites-available" {
    run type create_nginx_config
    [[ "$output" == *"/etc/nginx/sites-available/"* ]]
}

@test "create_nginx_config: creates symlink to sites-enabled" {
    run type create_nginx_config
    [[ "$output" == *"/etc/nginx/sites-enabled/"* ]]
}

@test "create_nginx_config: includes SSL certificate paths" {
    run type create_nginx_config
    [[ "$output" == *"/etc/letsencrypt/live/"* ]]
}

@test "create_nginx_config: blocks xmlrpc.php" {
    run type create_nginx_config
    [[ "$output" == *"xmlrpc.php"* ]]
    [[ "$output" == *"deny all"* ]]
}

@test "create_nginx_config: adds security headers" {
    run type create_nginx_config
    [[ "$output" == *"X-Frame-Options"* ]]
    [[ "$output" == *"X-Content-Type-Options"* ]]
}

@test "create_nginx_config: enables http2" {
    run type create_nginx_config
    [[ "$output" == *"http2 on"* ]]
}

#===============================================================================
# Tests for create_database function
#===============================================================================
@test "create_database: function exists" {
    run type create_database
    [ "$status" -eq 0 ]
}

@test "create_database: uses utf8mb4 character set" {
    run type create_database
    [[ "$output" == *"utf8mb4"* ]]
}

@test "create_database: uses utf8mb4_unicode_520_ci collation" {
    run type create_database
    [[ "$output" == *"utf8mb4_unicode_520_ci"* ]]
}

@test "create_database: grants all privileges" {
    run type create_database
    [[ "$output" == *"GRANT ALL PRIVILEGES"* ]]
}

@test "create_database: flushes privileges" {
    run type create_database
    [[ "$output" == *"FLUSH PRIVILEGES"* ]]
}

#===============================================================================
# Tests for install_wordpress function
#===============================================================================
@test "install_wordpress: function exists" {
    run type install_wordpress
    [ "$status" -eq 0 ]
}

@test "install_wordpress: uses wp core download" {
    run type install_wordpress
    [[ "$output" == *"wp core download"* ]]
}

@test "install_wordpress: uses wp core config" {
    run type install_wordpress
    [[ "$output" == *"wp core config"* ]]
}

@test "install_wordpress: uses wp core install" {
    run type install_wordpress
    [[ "$output" == *"wp core install"* ]]
}

@test "install_wordpress: deletes default plugins (akismet, hello)" {
    run type install_wordpress
    [[ "$output" == *"wp plugin delete"* ]]
}

@test "install_wordpress: deletes unused themes" {
    run type install_wordpress
    [[ "$output" == *"wp theme delete"* ]]
}

#===============================================================================
# Tests for setup_wp_cron function
#===============================================================================
@test "setup_wp_cron: function exists" {
    run type setup_wp_cron
    [ "$status" -eq 0 ]
}

@test "setup_wp_cron: creates cron entry for every 5 minutes" {
    run type setup_wp_cron
    [[ "$output" == *"*/5 * * * *"* ]]
}

@test "setup_wp_cron: uses wp cron event run" {
    run type setup_wp_cron
    [[ "$output" == *"wp cron event run --due-now"* ]]
}

@test "setup_wp_cron: disables WordPress internal cron" {
    run type setup_wp_cron
    [[ "$output" == *"DISABLE_WP_CRON"* ]]
}

#===============================================================================
# Tests for add_wordpress_site function (main orchestrator)
#===============================================================================
@test "add_wordpress_site: function exists" {
    run type add_wordpress_site
    [ "$status" -eq 0 ]
}

@test "add_wordpress_site: calls create_site_user" {
    run type add_wordpress_site
    [[ "$output" == *"create_site_user"* ]]
}

@test "add_wordpress_site: calls create_site_folders" {
    run type add_wordpress_site
    [[ "$output" == *"create_site_folders"* ]]
}

@test "add_wordpress_site: calls create_phpfpm_pool" {
    run type add_wordpress_site
    [[ "$output" == *"create_phpfpm_pool"* ]]
}

@test "add_wordpress_site: calls create_database" {
    run type add_wordpress_site
    [[ "$output" == *"create_database"* ]]
}
