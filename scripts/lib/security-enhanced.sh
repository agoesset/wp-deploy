#!/bin/bash
#===============================================================================
# Enhanced Security Functions
# Additional security hardening beyond basic setup
#===============================================================================

#===============================================================================
# Harden SSH Configuration
#===============================================================================
harden_ssh() {
    local sshd_config="/etc/ssh/sshd_config"
    
    header "Hardening SSH Configuration"
    
    if [[ ! -f "$sshd_config" ]]; then
        error "SSH config not found: ${sshd_config}"
        return 1
    fi
    
    backup_file "$sshd_config"
    
    step "Disabling root login..."
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    
    step "Disabling password authentication (key only)..."
    if confirm "Disable password authentication? (Require SSH key setup first)"; then
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
        warning "Password authentication disabled! Ensure you have SSH key access."
    fi
    
    step "Changing SSH port (optional)..."
    if confirm "Change default SSH port from 22?"; then
        local new_port
        new_port=$(input_prompt "Enter new SSH port (1024-65535)" "2222")
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ "$new_port" -ge 1024 ]] && [[ "$new_port" -le 65535 ]]; then
            sed -i "s/^#*Port.*/Port ${new_port}/" "$sshd_config"
            
            # Update UFW if active
            if ufw status | grep -q "Status: active"; then
                step "Updating UFW rules..."
                ufw allow "${new_port}/tcp"
                ufw delete allow ssh 2>/dev/null || true
            fi
            
            success "SSH port changed to ${new_port}"
            warning "Remember to use: ssh -p ${new_port} user@server"
        fi
    fi
    
    step "Limiting authentication attempts..."
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$sshd_config"
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' "$sshd_config"
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' "$sshd_config"
    
    step "Restarting SSH service..."
    systemctl restart sshd
    
    success "SSH hardened successfully!"
}

#===============================================================================
# Setup Automatic Security Updates
#===============================================================================
setup_auto_updates() {
    header "Setting Up Automatic Security Updates"
    
    step "Installing unattended-upgrades..."
    apt_install unattended-upgrades apt-listchanges
    
    step "Configuring automatic security updates..."
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED_UPGRADES'
// Automatically upgrade packages from these origin patterns
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

// Automatically reboot if needed
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Email notifications (optional)
// Unattended-Upgrade::Mail "admin@example.com";
UNATTENDED_UPGRADES

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTO_UPGRADES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
AUTO_UPGRADES

    step "Enabling unattended-upgrades service..."
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    success "Automatic security updates configured!"
    info "System will auto-update daily at 3:00 AM if needed"
}

#===============================================================================
# Enhanced Fail2ban Configuration for WordPress
#===============================================================================
setup_fail2ban_wordpress() {
    header "Configuring Fail2ban for WordPress Protection"
    
    # Create WordPress jail configuration
    cat > /etc/fail2ban/jail.local << 'FAIL2BAN_JAIL'
[DEFAULT]
# Ban for 1 hour after 5 failed attempts within 10 minutes
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
FAIL2BAN_JAIL

    # Create WordPress authentication filter
    cat > /etc/fail2ban/filter.d/wordpress-auth.conf << 'WP_FILTER'
[Definition]
failregex = ^\s*\S+\s+\S+\s+\S+\s+\[.*\]\s+"POST /wp-login.php.*" 200
            ^\s*\S+\s+\S+\s+\S+\s+\[.*\]\s+"POST /xmlrpc.php.*" 200
            ^\s*\S+\s+\S+\s+\S+\s+\[.*\]\s+"POST /wp-admin/admin-ajax.php.*" 403

ignoreregex =
FAIL2BAN_FILTER

    # Add WordPress jail
    cat >> /etc/fail2ban/jail.local << 'WP_JAIL'

[wordpress-auth]
enabled = true
filter = wordpress-auth
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 5
findtime = 300
bantime = 3600
WP_JAIL

    step "Restarting fail2ban..."
    systemctl restart fail2ban
    
    success "Fail2ban configured for WordPress protection!"
    echo ""
    info "Protected against:"
    info "  • SSH brute force (max 3 attempts)"
    info "  • WP login attacks (max 5 attempts)"
    info "  • Nginx auth failures"
    info "  • Bad bots (2 strikes = 24h ban)"
}

#===============================================================================
# Secure File Permissions for WordPress
#===============================================================================
secure_wordpress_permissions() {
    local domain="$1"
    local username="$2"
    local site_path="/home/${username}/${domain}/public"
    
    header "Securing File Permissions for ${domain}"
    
    if [[ ! -d "$site_path" ]]; then
        error "Site path not found: ${site_path}"
        return 1
    fi
    
    step "Setting ownership..."
    chown -R "${username}:${username}" "$site_path"
    
    step "Setting directory permissions (755)..."
    find "$site_path" -type d -exec chmod 755 {} \;
    
    step "Setting file permissions (644)..."
    find "$site_path" -type f -exec chmod 644 {} \;
    
    step "Securing wp-config.php (600)..."
    if [[ -f "${site_path}/wp-config.php" ]]; then
        chmod 600 "${site_path}/wp-config.php"
        chown "${username}:${username}" "${site_path}/wp-config.php"
    fi
    
    step "Securing .htaccess (644)..."
    if [[ -f "${site_path}/.htaccess" ]]; then
        chmod 644 "${site_path}/.htaccess"
    fi
    
    step "Setting uploads directory permissions (755)..."
    if [[ -d "${site_path}/wp-content/uploads" ]]; then
        chmod 755 "${site_path}/wp-content/uploads"
        chown -R "www-data:www-data" "${site_path}/wp-content/uploads"
    fi
    
    success "File permissions secured!"
    echo ""
    info "Permissions set:"
    info "  • Directories: 755"
    info "  • Files: 644"
    info "  • wp-config.php: 600 (read/write owner only)"
    info "  • uploads: 755 (owned by www-data)"
}

#===============================================================================
# Setup ModSecurity (Web Application Firewall)
#===============================================================================
setup_modsecurity() {
    header "Setting Up ModSecurity WAF"
    
    step "Installing ModSecurity..."
    apt_install libnginx-mod-security
    
    step "Configuring ModSecurity..."
    
    # Enable ModSecurity in nginx
    cat > /etc/nginx/modsecurity.conf << 'MODSEC'
# ModSecurity Configuration
SecRuleEngine On
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecResponseBodyAccess On
SecResponseBodyLimit 524288
SecResponseBodyMimeType text/plain text/html text/xml application/json

# Audit logging
SecAuditEngine RelevantOnly
SecAuditLog /var/log/modsec_audit.log
SecAuditLogParts ABIJDEFHZ

# Debug log
SecDebugLog /var/log/modsec_debug.log
SecDebugLogLevel 0

# Default rule set
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
MODSEC

    # Create nginx include
    mkdir -p /etc/nginx/modsec
    cat > /etc/nginx/modsec/main.conf << 'MODSEC_MAIN'
include /etc/nginx/modsecurity.conf
MODSEC_MAIN

    success "ModSecurity installed!"
    warning "Review /var/log/modsec_audit.log for blocked requests"
    info "To enable per-site, add to server block:"
    info '  modsecurity on;'
    info '  modsecurity_rules_file /etc/nginx/modsec/main.conf;'
}

#===============================================================================
# Database Security Hardening
#===============================================================================
harden_database() {
    header "Hardening Database Security"
    
    step "Removing anonymous users..."
    mariadb -u root -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    
    step "Removing remote root access..."
    mariadb -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    
    step "Removing test database..."
    mariadb -u root -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mariadb -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    
    step "Disabling LOAD DATA LOCAL INFILE..."
    cat > /etc/mysql/conf.d/security.cnf << 'MYSQL_SECURITY'
[mysqld]
# Security enhancements
local_infile = 0
skip-symbolic-links
secure-file-priv = /tmp
bind-address = 127.0.0.1

# Logging
log_error = /var/log/mysql/error.log
log_queries_not_using_indexes = 1
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
MYSQL_SECURITY

    step "Restarting MariaDB..."
    systemctl restart mariadb
    
    step "Reloading privileges..."
    mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    success "Database security hardened!"
    echo ""
    info "Changes applied:"
    info "  • Anonymous users removed"
    info "  • Remote root access disabled"
    info "  • Test database removed"
    info "  • LOAD DATA LOCAL INFILE disabled"
    info "  • Only local connections allowed (127.0.0.1)"
    info "  • Query logging enabled"
}

#===============================================================================
# Kernel Security Hardening (Sysctl)
#===============================================================================
harden_kernel() {
    header "Hardening Kernel Parameters"
    
    local sysctl_conf="/etc/sysctl.d/99-security.conf"
    
    cat > "$sysctl_conf" << 'SYSCTL_SECURITY'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if not needed (optional)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Increase system file descriptor limit
fs.file-max = 65535

# Increase memory mapping limits
vm.max_map_count = 262144
SYSCTL_SECURITY

    step "Applying kernel parameters..."
    sysctl -p "$sysctl_conf"
    
    success "Kernel security parameters applied!"
}

#===============================================================================
# Security Audit - Check for common issues
#===============================================================================
security_audit() {
    header "Security Audit Report"
    
    local issues=0
    
    echo -e "${BOLD}Checking Security Configuration...${NC}"
    echo ""
    
    # Check UFW status
    echo -n "UFW Firewall: "
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}✓ Active${NC}"
    else
        echo -e "${RED}✗ Not active${NC}"
        ((issues++))
    fi
    
    # Check Fail2ban
    echo -n "Fail2ban: "
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}✓ Running${NC}"
    else
        echo -e "${RED}✗ Not running${NC}"
        ((issues++))
    fi
    
    # Check SSH root login
    echo -n "SSH Root Login: "
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "${GREEN}✓ Disabled${NC}"
    else
        echo -e "${YELLOW}⚠ Enabled (recommend disabling)${NC}"
    fi
    
    # Check auto-updates
    echo -n "Auto Security Updates: "
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        echo -e "${GREEN}✓ Enabled${NC}"
    else
        echo -e "${YELLOW}⚠ Not enabled${NC}"
    fi
    
    # Check MariaDB remote access
    echo -n "MariaDB Remote Access: "
    if grep -q "bind-address.*127.0.0.1" /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || \
       grep -q "bind-address.*127.0.0.1" /etc/mysql/conf.d/security.cnf 2>/dev/null; then
        echo -e "${GREEN}✓ Restricted to localhost${NC}"
    else
        echo -e "${YELLOW}⚠ May allow remote connections${NC}"
    fi
    
    # Check for world-writable files
    echo -n "World-writable files in /home: "
    local ww_files
    ww_files=$(find /home -type f -perm -002 2>/dev/null | wc -l)
    if [[ "$ww_files" -eq 0 ]]; then
        echo -e "${GREEN}✓ None found${NC}"
    else
        echo -e "${RED}✗ ${ww_files} found${NC}"
        ((issues++))
    fi
    
    # Check SSL certificates expiry
    echo -n "SSL certificates expiring soon: "
    local expiring_certs=0
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        if [[ -f "$cert" ]]; then
            if ! openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null 2>&1; then
                ((expiring_certs++))
            fi
        fi
    done
    
    if [[ "$expiring_certs" -eq 0 ]]; then
        echo -e "${GREEN}✓ None expiring within 7 days${NC}"
    else
        echo -e "${YELLOW}⚠ ${expiring_certs} certificate(s) expiring soon${NC}"
    fi
    
    echo ""
    if [[ "$issues" -eq 0 ]]; then
        success "No critical security issues found!"
    else
        warning "Found ${issues} security issue(s) that should be addressed"
    fi
}

#===============================================================================
# Run all security hardening
#===============================================================================
run_all_security_hardening() {
    header "Running Complete Security Hardening"
    
    echo "This will apply all security hardening measures."
    echo ""
    warning "Some changes may require SSH key setup before applying!"
    echo ""
    
    if ! confirm "Proceed with full security hardening?"; then
        info "Security hardening cancelled"
        return 0
    fi
    
    harden_ssh
    setup_auto_updates
    setup_fail2ban_wordpress
    harden_database
    harden_kernel
    
    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "  Security hardening completed!"
    success "═══════════════════════════════════════════════════════════"
    echo ""
    info "Next steps:"
    info "  1. Review SSH key-based authentication is working"
    info "  2. Run 'security_audit' to verify all protections"
    info "  3. Monitor logs: /var/log/fail2ban.log, /var/log/auth.log"
}
