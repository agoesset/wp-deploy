#!/bin/bash
#===============================================================================
# Webserver Stack Installation Functions
#===============================================================================

# PHP Version (can be overridden)
PHP_VERSION="${PHP_VERSION:-8.3}"

#===============================================================================
# Install NGINX
#===============================================================================
install_nginx() {
    header "Installing NGINX"

    if check_command nginx; then
        warning "NGINX is already installed: $(nginx -v 2>&1)"
        if ! confirm "Do you want to reinstall/update?"; then
            return 0
        fi
    fi

    step \"Adding NGINX repository...\"
    # Ensure add-apt-repository is available
    if ! check_command add-apt-repository; then
        step \"Installing software-properties-common...\"
        apt_install software-properties-common
    fi
    add-apt-repository ppa:ondrej/nginx -y
    apt-get update

    step "Installing NGINX..."
    apt_install nginx

    step "Configuring NGINX..."
    configure_nginx

    step "Starting NGINX..."
    systemctl enable nginx
    systemctl start nginx

    if is_service_running nginx; then
        success "NGINX installed successfully!"
        nginx -v
    else
        error "NGINX failed to start"
        return 1
    fi
}

#===============================================================================
# Configure NGINX
#===============================================================================
configure_nginx() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local cpu_cores
    local open_files

    # Get system info
    cpu_cores=$(nproc)
    open_files=$(ulimit -n)

    info "CPU Cores: ${cpu_cores}, Open File Limit: ${open_files}"

    # Backup original config
    backup_file "$nginx_conf"

    # Write new configuration
    cat > "$nginx_conf" << 'NGINX_CONF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    ##
    # Basic Settings
    ##

    keepalive_timeout 15;
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    client_max_body_size 64m;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##

    access_log /var/log/nginx/access.log;

    ##
    # Gzip Settings
    ##

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    ##
    # Virtual Host Configs
    ##

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX_CONF

    # Test configuration
    if nginx -t; then
        success "NGINX configuration is valid"
    else
        error "NGINX configuration test failed"
        return 1
    fi
}

#===============================================================================
# Install PHP
#===============================================================================
install_php() {
    header "Installing PHP ${PHP_VERSION}"

    if check_command "php-fpm${PHP_VERSION}"; then
        warning "PHP ${PHP_VERSION} is already installed: $(php -v | head -n1)"
        if ! confirm "Do you want to reinstall/update?"; then
            return 0
        fi
    fi

    step "Adding PHP repository..."
    # Ensure add-apt-repository is available
    if ! check_command add-apt-repository; then
        step "Installing software-properties-common..."
        apt_install software-properties-common
    fi
    add-apt-repository ppa:ondrej/php -y
    apt-get update

    step "Installing PHP ${PHP_VERSION} and extensions..."
    apt_install \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-imagick" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-dev" \
        "php${PHP_VERSION}-imap" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-opcache" \
        "php${PHP_VERSION}-redis" \
        "php${PHP_VERSION}-soap" \
        "php${PHP_VERSION}-zip"

    step "Starting PHP-FPM..."
    systemctl enable "php${PHP_VERSION}-fpm"
    systemctl start "php${PHP_VERSION}-fpm"

    if is_service_running "php${PHP_VERSION}-fpm"; then
        success "PHP ${PHP_VERSION} installed successfully!"
        php -v
        echo ""
        info "Note: Default pool (www.conf) is active. Per-site pools will be created when adding WordPress sites."
    else
        error "PHP-FPM failed to start"
        return 1
    fi
}

#===============================================================================
# Install MariaDB
#===============================================================================
install_mariadb() {
    header "Installing MariaDB"

    if check_command mariadb; then
        warning "MariaDB is already installed: $(mariadb --version)"
        if ! confirm "Do you want to continue?"; then
            return 0
        fi
    fi

    step "Installing MariaDB server..."
    apt_install mariadb-server

    step "Starting MariaDB..."
    systemctl enable mariadb
    systemctl start mariadb

    if is_service_running mariadb; then
        success "MariaDB installed and running!"
        mariadb --version
    else
        error "MariaDB failed to start"
        return 1
    fi

    # Secure installation
    echo ""
    info "MariaDB Secure Installation"
    echo ""
    warning "You will now be prompted to secure your MariaDB installation."
    echo "Recommended answers:"
    echo "  - Switch to unix_socket authentication: n"
    echo "  - Change root password: Y (set a strong password)"
    echo "  - Remove anonymous users: Y"
    echo "  - Disallow root login remotely: Y"
    echo "  - Remove test database: Y"
    echo "  - Reload privilege tables: Y"
    echo ""

    if confirm "Run mysql_secure_installation now?"; then
        mysql_secure_installation
    else
        warning "Skipped mysql_secure_installation. Run it manually later for better security."
    fi
}

#===============================================================================
# Install Certbot
#===============================================================================
install_certbot() {
    header "Installing Certbot (Let's Encrypt)"

    if check_command certbot; then
        warning "Certbot is already installed: $(certbot --version 2>&1)"
        if ! confirm "Do you want to reinstall/update?"; then
            return 0
        fi
    fi

    step "Installing software-properties-common..."
    apt_install software-properties-common

    step "Adding universe repository..."
    add-apt-repository universe -y
    apt-get update

    step "Installing Certbot with NGINX plugin..."
    apt_install certbot python3-certbot-nginx

    success "Certbot installed successfully!"
    certbot --version
}

#===============================================================================
# Install WP-CLI
#===============================================================================
install_wpcli() {
    header "Installing WP-CLI"

    if check_command wp; then
        warning "WP-CLI is already installed: $(wp --version 2>/dev/null)"
        if ! confirm "Do you want to reinstall/update?"; then
            return 0
        fi
    fi

    step "Downloading WP-CLI..."
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

    step "Verifying WP-CLI..."
    if php wp-cli.phar --info > /dev/null 2>&1; then
        success "WP-CLI verification passed"
    else
        error "WP-CLI verification failed"
        rm -f wp-cli.phar
        return 1
    fi

    step "Installing WP-CLI to /usr/local/bin/wp..."
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp

    success "WP-CLI installed successfully!"
    wp --info
}

#===============================================================================
# Install Full Webserver Stack
#===============================================================================
install_full_stack() {
    header "Installing Full Webserver Stack"

    install_nginx
    install_php
    install_mariadb
    install_certbot
    install_wpcli

    success "Full webserver stack installation completed!"
}
