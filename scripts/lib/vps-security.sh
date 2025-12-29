#!/bin/bash
#===============================================================================
# VPS Security Setup Functions
#===============================================================================

#===============================================================================
# Setup Timezone
#===============================================================================
setup_timezone() {
    header "Setting up Timezone"

    info "Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone)"

    echo ""
    echo "Common timezones:"
    echo "  1. Asia/Jakarta (WIB)"
    echo "  2. Asia/Makassar (WITA)"
    echo "  3. Asia/Jayapura (WIT)"
    echo "  4. UTC"
    echo "  5. Custom"
    echo ""

    local choice
    read -rp "$(echo -e "${CYAN}Select timezone [1-5]: ${NC}")" choice

    local timezone
    case $choice in
        1) timezone="Asia/Jakarta" ;;
        2) timezone="Asia/Makassar" ;;
        3) timezone="Asia/Jayapura" ;;
        4) timezone="UTC" ;;
        5)
            timezone=$(input_prompt "Enter timezone (e.g., Asia/Singapore)" "Asia/Jakarta")
            ;;
        *)
            timezone="Asia/Jakarta"
            ;;
    esac

    step "Setting timezone to ${timezone}..."
    timedatectl set-timezone "$timezone"

    success "Timezone set to: $(timedatectl show --property=Timezone --value)"
}

#===============================================================================
# Update Software Packages
#===============================================================================
update_packages() {
    header "Updating Software Packages"

    step "Updating package lists..."
    wait_for_apt
    apt-get update -y

    step "Upgrading installed packages..."
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y

    step "Removing unused packages..."
    apt-get autoremove -y

    step "Cleaning up..."
    apt-get autoclean -y

    success "Software packages updated successfully!"

    # Check if reboot is required
    if [[ -f /var/run/reboot-required ]]; then
        warning "A system reboot is recommended."
        if confirm "Do you want to reboot now?"; then
            info "Rebooting system in 5 seconds..."
            sleep 5
            reboot
        fi
    fi
}

#===============================================================================
# Install and Configure UFW (Uncomplicated Firewall)
#===============================================================================
install_ufw() {
    header "Installing and Configuring UFW Firewall"

    step "Installing UFW..."
    apt_install ufw

    step "Configuring default policies..."
    ufw default deny incoming
    ufw default allow outgoing

    step "Allowing SSH (port 22)..."
    ufw allow ssh

    step "Allowing HTTP (port 80)..."
    ufw allow http

    step "Allowing HTTPS (port 443)..."
    ufw allow https

    # Show rules before enabling
    echo ""
    info "Firewall rules to be applied:"
    ufw show added

    echo ""
    if confirm "Enable UFW firewall with these rules?"; then
        # Enable UFW non-interactively
        echo "y" | ufw enable

        success "UFW firewall is now active!"
        echo ""
        ufw status verbose
    else
        warning "UFW was not enabled. You can enable it manually with: sudo ufw enable"
    fi
}

#===============================================================================
# Install Fail2ban
#===============================================================================
install_fail2ban() {
    header "Installing Fail2ban"

    step "Installing fail2ban..."
    apt_install fail2ban

    step "Starting fail2ban service..."
    systemctl enable fail2ban
    systemctl start fail2ban

    if is_service_running fail2ban; then
        success "Fail2ban is running and protecting your server!"
        
        # Show status
        echo ""
        info "Fail2ban status:"
        fail2ban-client status 2>/dev/null || true
    else
        error "Fail2ban failed to start. Check logs with: journalctl -u fail2ban"
    fi
}

#===============================================================================
# Run all security setup
#===============================================================================
run_all_security() {
    header "Running Full Security Setup"

    setup_timezone
    update_packages
    install_ufw
    install_fail2ban

    success "All security measures have been configured!"
}
