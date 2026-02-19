#===============================================================================
# Delete WordPress Site (Complete Cleanup)
# Removes: user, folders, PHP-FPM pool, NGINX config, database, SSL cert
#===============================================================================
delete_wordpress_site() {
    local domain="$1"
    local username="$2"
    local db_name="$3"
    local delete_db="${4:-true}"
    local delete_ssl="${5:-true}"

    header "Deleting WordPress Site: ${domain}"

    # Step 1: Stop services accessing the site
    info "Stopping services..."
    
    # Step 2: Remove NGINX configuration
    header "Removing NGINX Configuration"
    local nginx_available="/etc/nginx/sites-available/${domain}"
    local nginx_enabled="/etc/nginx/sites-enabled/${domain}"
    
    if [[ -f "$nginx_enabled" ]]; then
        step "Removing NGINX symlink..."
        rm -f "$nginx_enabled"
    fi
    
    if [[ -f "$nginx_available" ]]; then
        step "Removing NGINX config..."
        rm -f "$nginx_available"
        
        step "Testing NGINX configuration..."
        if nginx -t 2>/dev/null; then
            step "Reloading NGINX..."
            systemctl reload nginx || warning "Failed to reload NGINX"
            success "NGINX configuration removed"
        else
            warning "NGINX config test failed after removal"
            warning "Manual check may be needed: nginx -t"
        fi
    else
        info "No NGINX config found for ${domain}"
    fi

    # Step 3: Remove PHP-FPM pool
    header "Removing PHP-FPM Pool"
    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/${username}.conf"
    
    if [[ -f "$pool_conf" ]]; then
        step "Removing PHP-FPM pool..."
        rm -f "$pool_conf"
        
        step "Restarting PHP-FPM..."
        restart_service "php${PHP_VERSION}-fpm" || warning "Failed to restart PHP-FPM"
        success "PHP-FPM pool removed"
    else
        info "No PHP-FPM pool found for ${username}"
    fi

    # Step 4: Remove user and home directory
    header "Removing Linux User"
    if id "$username" &>/dev/null; then
        step "Removing user ${username} and home directory..."
        
        # Check if user has running processes
        if pgrep -u "$username" &>/dev/null; then
            warning "User ${username} has running processes"
            step "Killing processes..."
            pkill -9 -u "$username" 2>/dev/null || true
            sleep 1
        fi
        
        # Remove user with home directory
        if userdel -r "$username" 2>/dev/null; then
            success "User ${username} removed successfully"
        else
            # Try without -r first (in case home is already gone)
            if userdel "$username" 2>/dev/null; then
                success "User ${username} removed"
            else
                error "Failed to remove user ${username}"
                warning "Manual removal may be needed: sudo userdel -r ${username}"
            fi
        fi
    else
        info "User ${username} does not exist"
    fi

    # Remove site directory if still exists (backup location, etc.)
    local site_base="/home/${username}"
    if [[ -d "$site_base" ]]; then
        step "Removing site directory..."
        rm -rf "$site_base"
        success "Site directory removed"
    fi

    # Step 5: Remove database (optional)
    if [[ "$delete_db" == "true" ]]; then
        header "Removing Database"
        
        # Check if database exists
        local db_exists
        db_exists=$(mariadb -u root -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${db_name}';" 2>/dev/null | grep -c "$db_name" || echo "0")
        
        if [[ "$db_exists" -gt 0 ]]; then
            step "Dropping database ${db_name}..."
            if mariadb -u root -e "DROP DATABASE \`${db_name}\`;" 2>/dev/null; then
                success "Database ${db_name} dropped"
            else
                warning "Failed to drop database ${db_name}"
                info "Manual removal: DROP DATABASE \`${db_name}\`;"
            fi
            
            # Also remove database user
            local db_user="${username}_user"
            step "Removing database user ${db_user}..."
            mariadb -u root -e "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null || true
            mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        else
            info "Database ${db_name} does not exist"
        fi
        
        # Remove credentials file
        local creds_file="/root/.wp-deploy-credentials/${db_name}.txt"
        if [[ -f "$creds_file" ]]; then
            rm -f "$creds_file"
            info "Removed credentials file"
        fi
    fi

    # Step 6: Remove SSL certificate (optional)
    if [[ "$delete_ssl" == "true" ]]; then
        header "Removing SSL Certificate"
        local cert_dir="/etc/letsencrypt/live/${domain}"
        local cert_archive="/etc/letsencrypt/archive/${domain}"
        local cert_renewal="/etc/letsencrypt/renewal/${domain}.conf"
        
        if [[ -d "$cert_dir" ]]; then
            step "Revoking and deleting SSL certificate..."
            
            # Try to revoke first (non-critical)
            certbot revoke --cert-path "${cert_dir}/cert.pem" --non-interactive 2>/dev/null || true
            
            # Delete certificate files
            rm -rf "$cert_dir"
            rm -rf "$cert_archive"
            rm -f "$cert_renewal"
            
            success "SSL certificate removed"
        else
            info "No SSL certificate found for ${domain}"
        fi
    fi

    # Final cleanup - remove credentials directory if empty
    local creds_dir="/root/.wp-deploy-credentials"
    if [[ -d "$creds_dir" ]] && [[ -z "$(ls -A "$creds_dir" 2>/dev/null)" ]]; then
        rmdir "$creds_dir" 2>/dev/null || true
    fi

    # Summary
    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "  WordPress site deleted successfully!"
    success "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "  ${CYAN}Domain:${NC}      ${domain}"
    echo -e "  ${CYAN}User:${NC}        ${username}"
    [[ "$delete_db" == "true" ]] && echo -e "  ${CYAN}Database:${NC}    ${db_name} (removed)"
    [[ "$delete_ssl" == "true" ]] && echo -e "  ${CYAN}SSL Cert:${NC}    (removed)"
    echo ""
    info "All traces of ${domain} have been removed from the server"
}

#===============================================================================
# List all WordPress sites on server
#===============================================================================
list_wordpress_sites() {
    header "WordPress Sites on This Server"
    
    local found_sites=0
    
    # Look for NGINX configs that match WordPress patterns
    if [[ -d "/etc/nginx/sites-available" ]]; then
        echo -e "${BOLD}Sites found in NGINX:${NC}"
        echo ""
        
        for conf in /etc/nginx/sites-available/*; do
            if [[ -f "$conf" ]]; then
                local domain
                domain=$(basename "$conf")
                
                # Check if it's a WordPress site (contains wp-config.php pattern or php-fpm socket)
                if grep -q "php.*sock\|wp-config\|fastcgi_pass" "$conf" 2>/dev/null; then
                    local document_root
                    document_root=$(grep -oP 'root\s+\K[^;]+' "$conf" 2>/dev/null | head -1)
                    
                    local php_socket
                    php_socket=$(grep -oP 'fastcgi_pass\s+unix:\K[^;]+' "$conf" 2>/dev/null | head -1)
                    
                    local username="-"
                    if [[ -n "$php_socket" ]]; then
                        username=$(basename "$php_socket" | sed 's/php-//' | sed 's/\.sock$//')
                    fi
                    
                    local ssl_status="✗"
                    if grep -q "ssl_certificate" "$conf" 2>/dev/null; then
                        ssl_status="✓"
                    fi
                    
                    echo -e "  ${CYAN}Domain:${NC}    ${domain}"
                    echo -e "  ${CYAN}User:${NC}      ${username}"
                    echo -e "  ${CYAN}Path:${NC}      ${document_root:-N/A}"
                    echo -e "  ${CYAN}SSL:${NC}       ${ssl_status}"
                    echo ""
                    ((found_sites++))
                fi
            fi
        done
    fi
    
    # Also check for existing users with WordPress installations
    if [[ $found_sites -eq 0 ]]; then
        echo -e "${YELLOW}No WordPress sites found in NGINX configuration${NC}"
        echo ""
        
        # Look for users with /home/*/public/wp-config.php
        echo -e "${BOLD}Searching for orphaned installations...${NC}"
        local orphaned=0
        
        for user_home in /home/*; do
            if [[ -d "$user_home" ]]; then
                local user
                user=$(basename "$user_home")
                
                # Skip system users
                [[ "$user" =~ ^(root|ubuntu|debian|admin)$ ]] && continue
                
                for site_dir in "$user_home"/*/public/wp-config.php; do
                    if [[ -f "$site_dir" ]]; then
                        local site_path
                        site_path=$(dirname "$site_dir")
                        local domain_name
                        domain_name=$(basename "$(dirname "$site_path")")
                        
                        echo -e "  ${YELLOW}Orphaned:${NC} ${domain_name} (user: ${user})"
                        echo -e "    Path: ${site_path}"
                        ((orphaned++))
                    fi
                done
            fi
        done
        
        if [[ $orphaned -gt 0 ]]; then
            echo ""
            warning "Found ${orphaned} orphaned installation(s) without NGINX config"
            info "Use 'Delete Site' menu to clean them up"
        fi
    fi
    
    if [[ $found_sites -eq 0 ]] && [[ $orphaned -eq 0 ]]; then
        info "No WordPress sites found on this server"
    fi
}
