#!/bin/bash
#===============================================================================
# Performance Tuning Functions
# Auto-tunes configuration based on server specs (RAM, CPU)
#===============================================================================

#===============================================================================
# Detect server resources
#===============================================================================
detect_server_resources() {
    # RAM in MB
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))
    
    # CPU cores
    CPU_CORES=$(nproc)
    
    # Available for PHP-FPM (reserve 20% for system + MySQL + Redis)
    local reserved_mb=$((TOTAL_RAM_MB / 5))
    AVAILABLE_RAM_MB=$((TOTAL_RAM_MB - reserved_mb))
    
    # Estimate per PHP-FPM child memory (WordPress ~40-60MB per child)
    local php_memory_per_child=50
    
    # Calculate max children
    PHP_MAX_CHILDREN=$((AVAILABLE_RAM_MB / php_memory_per_child))
    
    # Ensure minimum values
    [[ $PHP_MAX_CHILDREN -lt 5 ]] && PHP_MAX_CHILDREN=5
    [[ $PHP_MAX_CHILDREN -gt 100 ]] && PHP_MAX_CHILDREN=100
    
    # Calculate derived values
    PHP_START_SERVERS=$((PHP_MAX_CHILDREN / 4))
    PHP_MIN_SPARE=$((PHP_START_SERVERS / 2))
    [[ $PHP_MIN_SPARE -lt 2 ]] && PHP_MIN_SPARE=2
    
    PHP_MAX_SPARE=$((PHP_START_SERVERS * 2))
    [[ $PHP_MAX_SPARE -gt PHP_MAX_CHILDREN ]] && PHP_MAX_SPARE=$PHP_MAX_CHILDREN
    
    export TOTAL_RAM_MB TOTAL_RAM_GB CPU_CORES AVAILABLE_RAM_MB
    export PHP_MAX_CHILDREN PHP_START_SERVERS PHP_MIN_SPARE PHP_MAX_SPARE
}

#===============================================================================
# Show current server resources
#===============================================================================
show_server_resources() {
    detect_server_resources
    
    header "Server Resources Detected"
    echo ""
    echo -e "  ${CYAN}Total RAM:${NC}        ${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB)"
    echo -e "  ${CYAN}CPU Cores:${NC}        ${CPU_CORES}"
    echo -e "  ${CYAN}Available RAM:${NC}    ${AVAILABLE_RAM_MB} MB (80% of total)"
    echo ""
    echo -e "  ${CYAN}Recommended PHP-FPM:${NC}"
    echo -e "    • max_children:      ${PHP_MAX_CHILDREN}"
    echo -e "    • start_servers:     ${PHP_START_SERVERS}"
    echo -e "    • min_spare:         ${PHP_MIN_SPARE}"
    echo -e "    • max_spare:         ${PHP_MAX_SPARE}"
    echo ""
    
    # Calculate NGINX worker connections
    local worker_conn=$((CPU_CORES * 1024))
    [[ $worker_conn -lt 4096 ]] && worker_conn=4096
    echo -e "  ${CYAN}Recommended NGINX:${NC}"
    echo -e "    • worker_processes:  auto (detected: ${CPU_CORES})"
    echo -e "    • worker_connections: ${worker_conn}"
    echo ""
}

#===============================================================================
# Tune NGINX configuration
#===============================================================================
tune_nginx_performance() {
    local nginx_conf="/etc/nginx/nginx.conf"
    
    detect_server_resources
    
    header "Tuning NGINX Performance"
    
    if [[ ! -f "$nginx_conf" ]]; then
        error "NGINX configuration not found: ${nginx_conf}"
        return 1
    fi
    
    # Backup original
    backup_file "$nginx_conf"
    
    # Calculate optimal values
    local worker_conn=$((CPU_CORES * 1024))
    [[ $worker_conn -lt 4096 ]] && worker_conn=4096
    
    step "Updating worker_connections to ${worker_conn}..."
    
    # Create optimized nginx.conf
    cat > "$nginx_conf" << NGINX_TUNE
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections ${worker_conn};
    multi_accept on;
    use epoll;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    types_hash_max_size 2048;
    client_max_body_size 64m;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    log_format detailed '\$remote_addr - \$remote_user [\$time_local] '
                       '"\$request" \$status \$body_bytes_sent '
                       '"\$http_referer" "\$http_user_agent" '
                       '\$request_time \$upstream_response_time';

    ##
    # Gzip Settings (Enhanced)
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1000;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    ##
    # Browser Cache Headers
    ##
    map \$sent_http_content_type \$expires {
        default                    off;
        text/html                  epoch;
        text/css                   max;
        application/javascript     max;
        ~image/                    max;
        ~font/                     max;
    }
    expires \$expires;

    ##
    # Rate Limiting Zones
    ##
    limit_req_zone \$binary_remote_addr zone=wp_login:10m rate=1r/s;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=10r/s;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX_TUNE

    # Test configuration
    step "Testing NGINX configuration..."
    if nginx -t; then
        success "NGINX configuration tuned successfully!"
        step "Reloading NGINX..."
        systemctl reload nginx
        
        echo ""
        info "Applied optimizations:"
        echo "  • worker_connections: ${worker_conn}"
        echo "  • keepalive_timeout: 30s"
        echo "  • Enhanced gzip settings"
        echo "  • Browser cache headers"
        echo "  • Rate limiting zones"
    else
        error "NGINX configuration test failed!"
        return 1
    fi
}

#===============================================================================
# Tune PHP-FPM configuration
#===============================================================================
tune_php_fpm() {
    detect_server_resources
    
    header "Tuning PHP-FPM Performance"
    
    local php_fpm_conf="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    local php_www_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    
    # Tune main php-fpm.conf
    if [[ -f "$php_fpm_conf" ]]; then
        backup_file "$php_fpm_conf"
        
        step "Optimizing php-fpm.conf..."
        
        # Update emergency_restart_threshold
        sed -i 's/;emergency_restart_threshold = 0/emergency_restart_threshold = 10/' "$php_fpm_conf"
        sed -i 's/;emergency_restart_interval = 0/emergency_restart_interval = 1m/' "$php_fpm_conf"
        sed -i 's/;process_control_timeout = 0/process_control_timeout = 10s/' "$php_fpm_conf"
        
        success "php-fpm.conf optimized"
    fi
    
    # Tune www.conf (default pool) or create optimized defaults
    if [[ -f "$php_www_conf" ]]; then
        backup_file "$php_www_conf"
        
        step "Optimizing www.conf pool..."
        
        # Create optimized pool config
        cat > "$php_www_conf" << PHPFPM_TUNE
[www]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm.sock
listen.owner = www-data
listen.group = www-data

; Dynamic PM based on server resources
pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN}
pm.start_servers = ${PHP_START_SERVERS}
pm.min_spare_servers = ${PHP_MIN_SPARE}
pm.max_spare_servers = ${PHP_MAX_SPARE}
pm.max_requests = 500
pm.process_idle_timeout = 10s

; Logging
php_admin_value[error_log] = /var/log/php-fpm/error.log
php_admin_flag[log_errors] = on

; Limits
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[max_input_vars] = 3000

; Upload limits
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size] = 64M

; Security
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_flag[allow_url_fopen] = off

; OPCache (will be overridden by opcache.ini)
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.memory_consumption] = 256
php_admin_value[opcache.max_accelerated_files] = 10000
PHPFPM_TUNE

        success "www.conf pool optimized"
    fi
    
    # Restart PHP-FPM
    step "Restarting PHP-FPM..."
    restart_service "php${PHP_VERSION}-fpm"
    
    echo ""
    success "PHP-FPM tuned for ${TOTAL_RAM_GB}GB RAM / ${CPU_CORES} cores!"
    info "Settings applied to www.conf (default pool)"
    info "New site pools will inherit these defaults"
}

#===============================================================================
# Tune OPCache configuration
#===============================================================================
tune_opcache() {
    detect_server_resources
    
    header "Tuning OPCache"
    
    local opcache_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/10-opcache.ini"
    
    # Calculate OPCache memory based on available RAM
    local opcache_mem=$((AVAILABLE_RAM_MB / 4))
    [[ $opcache_mem -lt 128 ]] && opcache_mem=128
    [[ $opcache_mem -gt 512 ]] && opcache_mem=512
    
    step "Configuring OPCache with ${opcache_mem}MB memory..."
    
    cat > "$opcache_ini" << OPCACHE_TUNE
; OPCache Optimized Configuration
; Auto-tuned for ${TOTAL_RAM_GB}GB RAM

opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=${opcache_mem}
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.revalidate_path=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.optimization_level=0xFFFFFFFF
opcache.jit_buffer_size=64M
opcache.jit=tracing

; File cache for faster restarts
opcache.file_cache=/var/cache/php/opcache
opcache.file_cache_only=0
opcache.file_cache_consistency_checks=1
OPCACHE_TUNE

    # Create file cache directory
    mkdir -p /var/cache/php/opcache
    chmod 755 /var/cache/php/opcache
    
    step "Restarting PHP-FPM..."
    restart_service "php${PHP_VERSION}-fpm"
    
    success "OPCache tuned with ${opcache_mem}MB!"
    echo ""
    info "OPCache features enabled:"
    echo "  • JIT compilation (64MB buffer)"
    echo "  • File cache for persistence"
    echo "  • Fast shutdown"
    echo "  • Optimized for WordPress"
}

#===============================================================================
# Apply all performance tunings
#===============================================================================
tune_all_performance() {
    show_server_resources
    
    echo ""
    if ! confirm "Apply all performance optimizations?"; then
        info "Tuning cancelled"
        return 0
    fi
    
    tune_nginx_performance
    echo ""
    tune_php_fpm
    echo ""
    tune_opcache
    
    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "  All performance optimizations applied!"
    success "═══════════════════════════════════════════════════════════"
    echo ""
    info "Monitor performance with:"
    echo "  • NGINX status: curl http://localhost/nginx_status"
    echo "  • PHP-FPM status: curl http://localhost/php-fpm_status"
    echo "  • OPCache status: php -r 'print_r(opcache_get_status());'"
}

#===============================================================================
# Create per-site optimized PHP-FPM pool
#===============================================================================
create_optimized_phpfpm_pool() {
    local username="$1"
    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/${username}.conf"
    local default_pool="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

    detect_server_resources

    header "Creating Optimized PHP-FPM Pool for ${username}"

    # Rename default pool if it exists (only needed for first site)
    if [[ -f "$default_pool" ]]; then
        step "Renaming default PHP-FPM pool (www.conf)..."
        mv "$default_pool" "${default_pool}.bak"
        info "Default pool renamed to www.conf.bak"
    fi

    if [[ -f "$pool_conf" ]]; then
        warning "Pool configuration already exists: ${pool_conf}"
        if ! confirm "Overwrite with optimized configuration?"; then
            return 0
        fi
    fi

    step "Creating optimized PHP-FPM pool configuration..."
    cat > "$pool_conf" << POOL_OPTIMIZED
[${username}]
user = ${username}
group = ${username}

listen = /run/php/php-${username}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

; Optimized PM settings (auto-tuned for ${TOTAL_RAM_GB}GB RAM)
pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN}
pm.start_servers = ${PHP_START_SERVERS}
pm.min_spare_servers = ${PHP_MIN_SPARE}
pm.max_spare_servers = ${PHP_MAX_SPARE}
pm.max_requests = 500
pm.process_idle_timeout = 10s
pm.status_path = /php-fpm_status

; Request timeout
request_timeout = 300
request_terminate_timeout = 300

; Limits (WordPress optimized)
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
php_admin_value[max_input_vars] = 3000
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size] = 64M

; OPCache
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.memory_consumption] = 128
php_admin_value[opcache.max_accelerated_files] = 5000

; Security
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_value[open_basedir] = /home/${username}:/tmp:/var/tmp
php_admin_flag[allow_url_fopen] = off

; Error logging
php_admin_value[error_log] = /home/${username}/logs/php-error.log
php_admin_flag[log_errors] = on
php_value[error_reporting] = E_ALL \& ~E_DEPRECATED \& ~E_STRICT
POOL_OPTIMIZED

    step "Testing PHP-FPM configuration..."
    if php-fpm${PHP_VERSION} -t; then
        success "PHP-FPM configuration is valid"
    else
        error "PHP-FPM configuration test failed"
        return 1
    fi

    step "Restarting PHP-FPM..."
    restart_service "php${PHP_VERSION}-fpm"

    success "Optimized PHP-FPM pool created for ${username}"
    echo ""
    info "Pool settings:"
    echo "  • max_children: ${PHP_MAX_CHILDREN}"
    echo "  • start_servers: ${PHP_START_SERVERS}"
    echo "  • Memory limit: 256M per child"
}
