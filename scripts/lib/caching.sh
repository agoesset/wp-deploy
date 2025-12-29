#!/bin/bash
#===============================================================================
# Caching Setup Functions
#===============================================================================

# PHP Version
PHP_VERSION="${PHP_VERSION:-8.3}"

#===============================================================================
# Install Redis
#===============================================================================
install_redis() {
    header "Installing Redis Server"

    if check_command redis-server; then
        warning "Redis is already installed"
        if is_service_running redis-server; then
            info "Redis is running"
        fi
        if ! confirm "Do you want to reinstall/update?"; then
            return 0
        fi
    fi

    step "Adding Redis repository..."
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt-get update

    step "Installing Redis server..."
    apt_install redis-server

    step "Enabling Redis service..."
    systemctl enable redis-server
    systemctl start redis-server

    step "Restarting PHP-FPM..."
    restart_service "php${PHP_VERSION}-fpm"

    if is_service_running redis-server; then
        success "Redis installed and running!"
        redis-server --version
        echo ""
        info "Redis is ready for use with WordPress Redis Object Cache plugin"
        info "Install plugin from: https://wordpress.org/plugins/redis-cache/"
    else
        error "Redis failed to start"
        return 1
    fi
}

#===============================================================================
# Configure NGINX for WP Super Cache
#===============================================================================
configure_wsc_nginx() {
    local domain="$1"
    local nginx_inc_dir="/etc/nginx/inc"
    local wsc_conf="${nginx_inc_dir}/wsc.conf"
    local nginx_site="/etc/nginx/sites-available/${domain}"

    header "Configuring NGINX for WP Super Cache"

    if [[ ! -f "$nginx_site" ]]; then
        error "NGINX configuration not found for ${domain}"
        error "Expected: ${nginx_site}"
        return 1
    fi

    # Create inc directory if it doesn't exist
    step "Creating NGINX include directory..."
    mkdir -p "$nginx_inc_dir"

    # Create WP Super Cache configuration
    step "Creating WP Super Cache NGINX configuration..."
    cat > "$wsc_conf" << 'WSC_CONF'
# WP Super Cache rules
set $cache_uri $request_uri;

# POST requests and urls with a query string should always go to PHP
if ($request_method = POST) {
    set $cache_uri 'null cache';
}

if ($query_string != "") {
    set $cache_uri 'null cache';
}

# Don't cache uris containing the following segments
if ($request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-(app|cron|login|register|mail).php|wp-.*.php|/feed/|index.php|wp-comments-popup.php|wp-links-opml.php|wp-locations.php|sitemap(_index)?.xml|[a-z0-9_-]+-sitemap([0-9]+)?.xml)") {
    set $cache_uri 'null cache';
}

# Don't use the cache for logged in users or recent commenters
if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_logged_in") {
    set $cache_uri 'null cache';
}

# Mobile detection
set $is_mobile 'non-mobile';
if ($http_x_wap_profile) {
    set $is_mobile 'mobile';
}

if ($http_profile) {
    set $is_mobile 'mobile';
}

if ($http_user_agent ~* (2.0\ MMP|240x320|400X240|AvantGo|BlackBerry|Blazer|Cellphone|Danger|DoCoMo|Elaine/3.0|EudoraWeb|Googlebot-Mobile|hiptop|IEMobile|KYOCERA/WX310K|LG/U990|MIDP-2.|MMEF20|MOT-V|NetFront|Newt|Nintendo\ Wii|Nitro|Nokia|Opera\ Mini|Palm|PlayStation\ Portable|portalmmm|Proxinet|ProxiNet|SHARP-TQ-GX10|SHG-i900|Small|SonyEricsson|Symbian\ OS|SymbianOS|TS21i-10|UP.Browser|UP.Link|webOS|Windows\ CE|WinWAP|YahooSeeker/M1A1-R2D2|iPhone|iPod|Android|BlackBerry9530|LG-TU915\ Obigo|LGE\ VX|webOS|Nokia5800)) {
    set $is_mobile 'mobile';
}

# Build cache filename
set $cache_file 'index';
if ($scheme = "https") {
    set $cache_file "${cache_file}-https";
}

if ($is_mobile = "mobile") {
    set $cache_file "${cache_file}-mobile";
}

set $cache_file "${cache_file}.html";

# Use cached or actual file if they exist, otherwise pass request to WordPress
location / {
    try_files /wp-content/cache/supercache/$http_host/$cache_uri/$cache_file $uri $uri/ /index.php?$args;
}
WSC_CONF

    success "WP Super Cache configuration created: ${wsc_conf}"

    # Update NGINX site configuration
    step "Updating NGINX site configuration..."
    
    # Check if already includes wsc.conf
    if grep -q "include /etc/nginx/inc/wsc.conf" "$nginx_site"; then
        info "NGINX site already includes WP Super Cache configuration"
    else
        # Backup the site config
        backup_file "$nginx_site"

        # Replace the location / block with include using sed
        # This handles multi-line replacement
        step "Replacing location / block with WSC include..."
        
        # Use perl for multi-line replacement (more reliable than sed for this)
        if command -v perl &>/dev/null; then
            perl -i -p0e 's/location \/ \{\s*try_files \$uri \$uri\/ \/index\.php\?\$args;\s*\}/include \/etc\/nginx\/inc\/wsc.conf;/gs' "$nginx_site"
            success "Location block replaced with WSC include"
        else
            # Fallback: use sed with pattern
            # First, create a temporary approach
            sed -i 's|location / {|# WSC REPLACED\n    include /etc/nginx/inc/wsc.conf;\n    # OLD: location / {|g' "$nginx_site"
            sed -i '/# OLD: location \/ {/,/^[[:space:]]*}$/d' "$nginx_site"
            success "Location block replaced with WSC include"
        fi
    fi

    # Test NGINX configuration
    step "Testing NGINX configuration..."
    if nginx -t; then
        success "NGINX configuration is valid"
        restart_service nginx
    else
        error "NGINX configuration test failed!"
        warning "Restoring backup..."
        # Find the most recent backup
        local backup_file=$(ls -t "${nginx_site}.bak."* 2>/dev/null | head -1)
        if [[ -n "$backup_file" ]]; then
            cp "$backup_file" "$nginx_site"
            nginx -t && restart_service nginx
            warning "Backup restored. Please check configuration manually."
        fi
        return 1
    fi

    echo ""
    success "WP Super Cache NGINX configuration completed!"
    echo ""
    info "Next steps:"
    echo "  1. Install WP Super Cache plugin in WordPress"
    echo "  2. Enable caching in WP Super Cache settings"
    echo "  3. Test your site to verify caching is working"
}

#===============================================================================
# Install all caching components
#===============================================================================
install_all_caching() {
    header "Installing All Caching Components"

    install_redis

    echo ""
    info "Redis is installed. WP Super Cache NGINX configuration must be done per-site."
    info "Use option 2 to configure WP Super Cache for a specific site."
}
