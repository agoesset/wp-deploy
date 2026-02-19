#!/bin/bash
#===============================================================================
# Rollback Functions Library
# Provides cleanup and rollback capabilities for failed operations
#===============================================================================

# Global array to track created resources for rollback
WP_CREATED_RESOURCES=()

#===============================================================================
# Add resource to rollback tracking
#===============================================================================
add_rollback_resource() {
    local resource_type="$1"
    local resource_path="$2"
    WP_CREATED_RESOURCES+=("${resource_type}:${resource_path}")
}

#===============================================================================
# Perform rollback of all tracked resources
#===============================================================================
rollback_resources() {
    if [[ ${#WP_CREATED_RESOURCES[@]} -eq 0 ]]; then
        return 0
    fi

    warning "Rolling back changes due to error..."
    
    # Process in reverse order (LIFO)
    for ((i=${#WP_CREATED_RESOURCES[@]}-1; i>=0; i--)); do
        local resource="${WP_CREATED_RESOURCES[$i]}"
        local type="${resource%%:*}"
        local path="${resource#*:}"
        
        case "$type" in
            user)
                if id "$path" &>/dev/null; then
                    info "Removing user: ${path}"
                    userdel -r "$path" 2>/dev/null || true
                fi
                ;;
            folder)
                if [[ -d "$path" ]]; then
                    info "Removing folder: ${path}"
                    rm -rf "$path"
                fi
                ;;
            phpfpm_pool)
                if [[ -f "$path" ]]; then
                    info "Removing PHP-FPM pool: ${path}"
                    rm -f "$path"
                    restart_service "php${PHP_VERSION:-8.3}-fpm" || true
                fi
                ;;
            nginx_site)
                if [[ -f "$path" ]]; then
                    info "Removing NGINX config: ${path}"
                    rm -f "$path"
                fi
                # Also remove symlink
                local domain
                domain=$(basename "$path")
                rm -f "/etc/nginx/sites-enabled/${domain}" 2>/dev/null || true
                ;;
            database)
                info "Note: Database '${path}' was created but not removed (manual cleanup required)"
                ;;
        esac
    done
    
    WP_CREATED_RESOURCES=()
    info "Rollback completed"
}

#===============================================================================
# Clear rollback tracking (call on success)
#===============================================================================
clear_rollback_resources() {
    WP_CREATED_RESOURCES=()
}

#===============================================================================
# Cleanup function to be called on script exit/error
# Usage: trap 'cleanup_on_error' ERR EXIT
#===============================================================================
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        rollback_resources
    fi
}

#===============================================================================
# Check DNS resolution before SSL
#===============================================================================
check_dns_resolution() {
    local domain="$1"
    local expected_ip="${2:-}"
    
    info "Checking DNS resolution for ${domain}..."
    
    # Get the IP that domain resolves to
    local resolved_ip
    resolved_ip=$(dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    
    if [[ -z "$resolved_ip" ]]; then
        resolved_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
    fi
    
    if [[ -z "$resolved_ip" ]]; then
        error "DNS lookup failed for ${domain}"
        error "Make sure the domain's A record points to this server"
        return 1
    fi
    
    info "Domain ${domain} resolves to: ${resolved_ip}"
    
    # If expected IP provided, verify it matches
    if [[ -n "$expected_ip" && "$resolved_ip" != "$expected_ip" ]]; then
        warning "Domain resolves to ${resolved_ip}, but server IP is ${expected_ip}"
        return 1
    fi
    
    return 0
}

#===============================================================================
# Validate SSL certificate exists and is not expired
#===============================================================================
validate_ssl_certificate() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
    
    if [[ ! -f "$cert_path" ]]; then
        return 1
    fi
    
    # Check if certificate is valid and not expired
    if openssl x509 -in "$cert_path" -noout -checkend 86400 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Safe database creation with credentials file
#===============================================================================
create_database_safe() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    local creds_file="/root/.wp-deploy-credentials/${db_name}.txt"

    header "Creating Database: ${db_name}"

    # Ensure credentials directory exists
    mkdir -p "$(dirname "$creds_file")"
    chmod 700 "$(dirname "$creds_file")"

    info "Database credentials will be saved to: ${creds_file}"
    
    # Create SQL commands
    local sql_commands="
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
"

    # Execute SQL
    if echo "$sql_commands" | mariadb -u root -p 2>/dev/null; then
        # Save credentials securely
        cat > "$creds_file" << EOF
Database: ${db_name}
Username: ${db_user}
Password: ${db_pass}
Created: $(date)
EOF
        chmod 600 "$creds_file"
        
        success "Database ${db_name} created successfully!"
        success "Credentials saved to ${creds_file}"
        return 0
    else
        error "Failed to create database"
        return 1
    fi
}

#===============================================================================
# Check if WordPress is already installed at path
#===============================================================================
is_wordpress_installed() {
    local site_path="$1"
    [[ -f "${site_path}/wp-config.php" ]]
}

#===============================================================================
# Enhanced input with validation
#===============================================================================
input_prompt_validated() {
    local message="$1"
    local default="$2"
    local validation_func="$3"
    local error_msg="${4:-Invalid input. Please try again.}"
    local response
    local attempts=0
    local max_attempts=3

    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -n "$default" ]]; then
            echo -ne "${CYAN}${message}${NC} [${DIM}${default}${NC}]: " >/dev/tty
        else
            echo -ne "${CYAN}${message}${NC}: " >/dev/tty
        fi

        read -r response </dev/tty

        # Use default if empty
        if [[ -z "$response" && -n "$default" ]]; then
            response="$default"
        fi

        # Validate if function provided
        if [[ -n "$validation_func" ]]; then
            if $validation_func "$response"; then
                echo "$response"
                return 0
            else
                error "$error_msg"
                attempts=$((attempts + 1))
            fi
        else
            echo "$response"
            return 0
        fi
    done

    error "Maximum attempts exceeded"
    return 1
}

#===============================================================================
# Check system resources before installation
#===============================================================================
check_system_resources() {
    header "Checking System Resources"

    # Check RAM
    local ram_gb
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $ram_gb -lt 1 ]]; then
        warning "Low RAM detected: ${ram_gb}GB (Recommended: 1GB+)"
    else
        info "RAM: ${ram_gb}GB ✓"
    fi

    # Check disk space
    local disk_gb
    disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $disk_gb -lt 5 ]]; then
        warning "Low disk space: ${disk_gb}GB free (Recommended: 5GB+)"
    else
        info "Disk: ${disk_gb}GB free ✓"
    fi

    # Check if ports 80 and 443 are available
    if is_port_open 80; then
        info "Port 80: In use"
    else
        info "Port 80: Available ✓"
    fi

    if is_port_open 443; then
        info "Port 443: In use"
    else
        info "Port 443: Available ✓"
    fi
}
