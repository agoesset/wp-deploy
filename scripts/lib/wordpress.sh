#!/bin/bash
#===============================================================================
# WordPress Site Setup Functions
#===============================================================================

# PHP Version
PHP_VERSION="${PHP_VERSION:-8.3}"

#===============================================================================
# Create Linux user for site
#===============================================================================
create_site_user() {
    local username="$1"

    header "Creating User: ${username}"

    if id "$username" &>/dev/null; then
        warning "User ${username} already exists"
        return 0
    fi

    step "Creating user ${username}..."
    useradd -m -s /bin/bash "$username"

    step "Adding www-data to ${username} group..."
    usermod -a -G "$username" www-data

    success "User ${username} created successfully!"
}

#===============================================================================
# Create folder structure for site
#===============================================================================
create_site_folders() {
    local username="$1"
    local domain="$2"
    local site_path="/home/${username}/${domain}"

    header "Creating Folder Structure"

    step "Creating public directory..."
    mkdir -p "${site_path}/public"

    step "Creating logs directory..."
    mkdir -p "${site_path}/logs"

    step "Setting ownership..."
    chown -R "${username}:${username}" "/home/${username}"

    success "Folder structure created at ${site_path}"
}

#===============================================================================
# Create PHP-FPM Pool
#===============================================================================
create_phpfpm_pool() {
    local username="$1"
    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/${username}.conf"
    local default_pool="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

    header "Creating PHP-FPM Pool for ${username}"

    # Rename default pool if it exists (only needed for first site)
    if [[ -f "$default_pool" ]]; then
        step "Renaming default PHP-FPM pool (www.conf)..."
        mv "$default_pool" "${default_pool}.bak"
        info "Default pool renamed to www.conf.bak"
    fi

    if [[ -f "$pool_conf" ]]; then
        warning "Pool configuration already exists: ${pool_conf}"
        if ! confirm "Overwrite existing configuration?"; then
            return 0
        fi
    fi

    step "Creating PHP-FPM pool configuration..."
    cat > "$pool_conf" << POOL_CONF
[${username}]
user = ${username}
group = ${username}

listen = /run/php/php-${username}.sock

listen.owner = www-data
listen.group = www-data

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

php_admin_value[memory_limit] = 256M
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size] = 64M
php_admin_value[opcache.enable_file_override] = 1
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
POOL_CONF

    step "Testing PHP-FPM configuration..."
    if php-fpm${PHP_VERSION} -t; then
        success "PHP-FPM configuration is valid"
    else
        error "PHP-FPM configuration test failed"
        return 1
    fi

    step "Restarting PHP-FPM..."
    restart_service "php${PHP_VERSION}-fpm"

    success "PHP-FPM pool created: /run/php/php-${username}.sock"
}

#===============================================================================
# Get SSL Certificate
#===============================================================================
get_ssl_certificate() {
    local domain="$1"
    local with_www="${2:-true}"

    header "Getting SSL Certificate for ${domain}"

    warning "Make sure your domain's A record is pointing to this server's IP!"
    info "Server IP: $(get_public_ip)"
    echo ""

    if ! confirm "Is the DNS configured correctly?"; then
        warning "Skipping SSL certificate. You can run this later with:"
        echo "  sudo certbot --nginx certonly -d ${domain} -d www.${domain}"
        return 1
    fi

    step "Requesting SSL certificate from Let's Encrypt..."
    
    local certbot_cmd="certbot --nginx certonly -d ${domain}"
    if [[ "$with_www" == "true" ]]; then
        certbot_cmd="${certbot_cmd} -d www.${domain}"
    fi

    if eval "$certbot_cmd"; then
        success "SSL certificate obtained successfully!"
        return 0
    else
        error "Failed to obtain SSL certificate"
        return 1
    fi
}

#===============================================================================
# Create NGINX Site Configuration
#===============================================================================
create_nginx_config() {
    local domain="$1"
    local username="$2"
    local with_ssl="${3:-true}"
    local with_www="${4:-true}"
    
    local site_path="/home/${username}/${domain}"
    local nginx_available="/etc/nginx/sites-available/${domain}"
    local nginx_enabled="/etc/nginx/sites-enabled/${domain}"

    header "Creating NGINX Configuration for ${domain}"

    if [[ -f "$nginx_available" ]]; then
        warning "NGINX configuration already exists: ${nginx_available}"
        if ! confirm "Overwrite existing configuration?"; then
            return 0
        fi
    fi

    step "Creating NGINX site configuration..."

    if [[ "$with_ssl" == "true" ]]; then
        # SSL Configuration
        cat > "$nginx_available" << NGINX_SSL_CONF
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;

    server_name ${domain} www.${domain};

    return 301 https://www.${domain}\$request_uri;
}

# Redirect non-www HTTPS to www
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

    return 301 https://www.${domain}\$request_uri;
}

# Main server block
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name www.${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

    access_log ${site_path}/logs/access.log;
    error_log ${site_path}/logs/error.log;

    root ${site_path}/public/;
    index index.php;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php-${username}.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
    }

    # Block xmlrpc.php
    location = /xmlrpc.php {
        deny all;
    }

    # Block access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~ /wp-config.php {
        deny all;
    }
}
NGINX_SSL_CONF
    else
        # Non-SSL Configuration (for testing)
        cat > "$nginx_available" << NGINX_CONF
server {
    listen 80;
    listen [::]:80;

    server_name ${domain} www.${domain};

    access_log ${site_path}/logs/access.log;
    error_log ${site_path}/logs/error.log;

    root ${site_path}/public/;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php-${username}.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
    }

    location = /xmlrpc.php {
        deny all;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX_CONF
    fi

    step "Creating symlink to sites-enabled..."
    ln -sf "$nginx_available" "$nginx_enabled"

    step "Testing NGINX configuration..."
    if nginx -t; then
        success "NGINX configuration is valid"
    else
        error "NGINX configuration test failed"
        rm -f "$nginx_enabled"
        return 1
    fi

    step "Reloading NGINX..."
    restart_service nginx

    success "NGINX configuration created for ${domain}"
}

#===============================================================================
# Create Database
#===============================================================================
create_database() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    header "Creating Database: ${db_name}"

    info "You will be prompted for MariaDB root password"
    echo ""

    step "Creating database and user..."
    
    # Create SQL commands
    local sql_commands="
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
"

    # Execute SQL
    if echo "$sql_commands" | mariadb -u root -p; then
        success "Database ${db_name} created successfully!"
        success "User ${db_user} created with full privileges"
    else
        error "Failed to create database"
        return 1
    fi
}

#===============================================================================
# Install WordPress
#===============================================================================
install_wordpress() {
    local domain="$1"
    local username="$2"
    local db_name="$3"
    local db_user="$4"
    local db_pass="$5"
    local site_title="$6"
    local admin_user="$7"
    local admin_email="$8"
    local admin_pass="$9"
    
    local site_path="/home/${username}/${domain}/public"
    local site_url="https://www.${domain}"

    header "Installing WordPress"

    step "Downloading WordPress..."
    sudo -u "$username" bash -c "cd ${site_path} && wp core download"

    step "Creating wp-config.php..."
    sudo -u "$username" bash -c "cd ${site_path} && wp core config --dbname='${db_name}' --dbuser='${db_user}' --dbpass='${db_pass}'"

    step "Installing WordPress..."
    sudo -u "$username" bash -c "cd ${site_path} && wp core install --skip-email --url='${site_url}' --title='${site_title}' --admin_user='${admin_user}' --admin_email='${admin_email}' --admin_password='${admin_pass}'"

    step "Cleaning up default plugins and themes..."
    sudo -u "$username" bash -c "cd ${site_path} && wp plugin delete akismet hello 2>/dev/null || true"
    sudo -u "$username" bash -c "cd ${site_path} && wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true"

    success "WordPress installed successfully!"
    echo ""
    info "Site URL: ${site_url}"
    info "Admin URL: ${site_url}/wp-admin"
    info "Admin User: ${admin_user}"
    info "Admin Email: ${admin_email}"
}

#===============================================================================
# Add WordPress Site (Main Function)
#===============================================================================
add_wordpress_site() {
    local domain="$1"
    local username="$2"
    local db_name="$3"
    local db_user="$4"
    local db_pass="$5"
    local site_title="$6"
    local admin_user="$7"
    local admin_email="$8"
    local admin_pass="$9"

    header "Adding WordPress Site: ${domain}"

    # Step 1: Create user
    create_site_user "$username"

    # Step 2: Create folders
    create_site_folders "$username" "$domain"

    # Step 3: Create PHP-FPM pool
    create_phpfpm_pool "$username"

    # Step 4: Get SSL certificate
    local has_ssl="false"
    if get_ssl_certificate "$domain"; then
        has_ssl="true"
    fi

    # Step 5: Create NGINX config
    create_nginx_config "$domain" "$username" "$has_ssl"

    # Step 6: Create database
    create_database "$db_name" "$db_user" "$db_pass"

    # Step 7: Install WordPress
    install_wordpress "$domain" "$username" "$db_name" "$db_user" "$db_pass" \
                     "$site_title" "$admin_user" "$admin_email" "$admin_pass"

    # Summary
    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "  WordPress site created successfully!"
    success "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "  ${CYAN}Domain:${NC}        ${domain}"
    echo -e "  ${CYAN}Site Path:${NC}     /home/${username}/${domain}/public"
    echo -e "  ${CYAN}Database:${NC}      ${db_name}"
    echo -e "  ${CYAN}DB User:${NC}       ${db_user}"
    echo -e "  ${CYAN}DB Password:${NC}   ${db_pass}"
    echo ""
    echo -e "  ${CYAN}Admin URL:${NC}     https://www.${domain}/wp-admin"
    echo -e "  ${CYAN}Admin User:${NC}    ${admin_user}"
    echo -e "  ${CYAN}Admin Email:${NC}   ${admin_email}"
    echo -e "  ${CYAN}Admin Pass:${NC}    ${admin_pass}"
    echo ""
    warning "Save these credentials securely!"
}

#===============================================================================
# Setup WordPress Cron
#===============================================================================
setup_wp_cron() {
    local username="$1"
    local domain="$2"
    local site_path="/home/${username}/${domain}/public"

    header "Setting up WordPress Cron"

    step "Adding cron job for ${username}..."
    
    # Create cron entry
    local cron_entry="*/5 * * * * cd ${site_path}; /usr/local/bin/wp cron event run --due-now >/dev/null 2>&1"
    
    # Add to user's crontab
    (sudo -u "$username" crontab -l 2>/dev/null | grep -v "wp cron"; echo "$cron_entry") | sudo -u "$username" crontab -

    step "Disabling WordPress internal cron..."
    sudo -u "$username" bash -c "cd ${site_path} && wp config set DISABLE_WP_CRON true --raw"

    success "WordPress cron configured!"
    info "Cron will run every 5 minutes"
}
