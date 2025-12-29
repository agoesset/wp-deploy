#!/bin/bash
#===============================================================================
#
#          FILE: vps-setup.sh
#
#         USAGE: ./vps-setup.sh [options]
#
#   DESCRIPTION: Dynamic VPS Setup Script for WordPress Hosting
#                Based on WPBogor Meetup-08 Tutorial
#
#       OPTIONS: --help    Show help message
#                --version Show version
#
#        AUTHOR: Generated from meetup-08 tutorial
#       VERSION: 1.0.0
#===============================================================================

set -e

#===============================================================================
# Configuration
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
LOG_FILE="/var/log/vps-setup.log"
VERSION="1.0.0"

# PHP Version
PHP_VERSION="8.3"

#===============================================================================
# Load Libraries
#===============================================================================
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/vps-security.sh"
source "${LIB_DIR}/webserver.sh"
source "${LIB_DIR}/wordpress.sh"
source "${LIB_DIR}/caching.sh"

#===============================================================================
# Main Menu Functions
#===============================================================================

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
 ╔═════════════════════════════════════════════════════╗
 ║                                                     ║
 ║              ██╗   ██╗██████╗ ███████╗              ║
 ║              ██║   ██║██╔══██╗██╔════╝              ║
 ║              ██║   ██║██████╔╝███████╗              ║
 ║              ╚██╗ ██╔╝██╔═══╝ ╚════██║              ║
 ║               ╚████╔╝ ██║     ███████║              ║
 ║                ╚═══╝  ╚═╝     ╚══════╝              ║
 ║                                                     ║
 ║      ███████╗███████╗████████╗██╗   ██╗██████╗      ║
 ║      ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗     ║
 ║      ███████╗█████╗     ██║   ██║   ██║██████╔╝     ║
 ║      ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝      ║
 ║      ███████║███████╗   ██║   ╚██████╔╝██║          ║
 ║      ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝          ║
 ║                                                     ║
 ║        Dynamic VPS Setup for WordPress Hosting      ║
 ║               Based on WPBogor Tutorial             ║
 ║                       v1.0.0                        ║
 ║                                                     ║
 ╚═════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

show_main_menu() {
    echo ""
    echo -e "${BOLD}Main Menu${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 🔐 Initial VPS Setup (Security)"
    echo -e "  ${GREEN}2.${NC} 🌐 Install Webserver Stack"
    echo -e "  ${GREEN}3.${NC} 📝 Add WordPress Site"
    echo -e "  ${GREEN}4.${NC} 🚀 Setup Caching (Redis & WP Super Cache)"
    echo -e "  ${GREEN}5.${NC} ⏰ Setup Cron"
    echo -e "  ${GREEN}6.${NC} 📦 Full Installation (All of the above)"
    echo ""
    echo -e "  ${YELLOW}i.${NC} ℹ️  System Information"
    echo -e "  ${RED}0.${NC} 🚪 Exit"
    echo ""
    echo -e "${DIM}─────────────────────────────────────────${NC}"
}

show_security_menu() {
    echo ""
    echo -e "${BOLD}🔒 VPS Security Setup${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} Setup Timezone"
    echo -e "  ${GREEN}2.${NC} Update Software Packages"
    echo -e "  ${GREEN}3.${NC} Install & Configure Firewall (UFW)"
    echo -e "  ${GREEN}4.${NC} Install Fail2ban"
    echo -e "  ${GREEN}5.${NC} Run All Security Setup"
    echo ""
    echo -e "  ${RED}0.${NC} Back to Main Menu"
    echo ""
    echo -e "${DIM}─────────────────────────────────────────${NC}"
}

show_webserver_menu() {
    echo ""
    echo -e "${BOLD}🌐 Webserver Stack Installation${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} Install NGINX"
    echo -e "  ${GREEN}2.${NC} Install PHP ${PHP_VERSION}"
    echo -e "  ${GREEN}3.${NC} Install MariaDB"
    echo -e "  ${GREEN}4.${NC} Install Certbot (Let's Encrypt)"
    echo -e "  ${GREEN}5.${NC} Install WP-CLI"
    echo -e "  ${GREEN}6.${NC} Install Full Stack (All of the above)"
    echo ""
    echo -e "  ${RED}0.${NC} Back to Main Menu"
    echo ""
    echo -e "${DIM}─────────────────────────────────────────${NC}"
}

show_caching_menu() {
    echo ""
    echo -e "${BOLD}⚡ Caching Setup${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} Install Redis Server"
    echo -e "  ${GREEN}2.${NC} Configure NGINX for WP Super Cache"
    echo -e "  ${GREEN}3.${NC} Install All Caching Components"
    echo ""
    echo -e "  ${RED}0.${NC} Back to Main Menu"
    echo ""
    echo -e "${DIM}─────────────────────────────────────────${NC}"
}

#===============================================================================
# Menu Handlers
#===============================================================================

handle_security_menu() {
    local choice
    while true; do
        show_banner
        show_security_menu
        read -rp "$(echo -e "${CYAN}Pilih opsi [0-5]: ${NC}")" choice

        case $choice in
            1) setup_timezone ;;
            2) update_packages ;;
            3) install_ufw ;;
            4) install_fail2ban ;;
            5)
                info "Running all security setup..."
                setup_timezone
                update_packages
                install_ufw
                install_fail2ban
                success "All security setup completed!"
                ;;
            0) break ;;
            *) error "Invalid option. Please try again." ;;
        esac

        if [[ "$choice" != "0" ]]; then
            echo ""
            read -rp "Press Enter to continue..."
        fi
    done
}

handle_webserver_menu() {
    local choice
    while true; do
        show_banner
        show_webserver_menu
        read -rp "$(echo -e "${CYAN}Pilih opsi [0-6]: ${NC}")" choice

        case $choice in
            1) install_nginx ;;
            2) install_php ;;
            3) install_mariadb ;;
            4) install_certbot ;;
            5) install_wpcli ;;
            6)
                info "Installing full webserver stack..."
                install_nginx
                install_php
                install_mariadb
                install_certbot
                install_wpcli
                success "Full webserver stack installed!"
                ;;
            0) break ;;
            *) error "Invalid option. Please try again." ;;
        esac

        if [[ "$choice" != "0" ]]; then
            echo ""
            read -rp "Press Enter to continue..."
        fi
    done
}

handle_wordpress_menu() {
    show_banner
    echo ""
    echo -e "${BOLD}📝 Add New WordPress Site${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""

    # Collect site information
    local domain username db_name db_user db_pass site_title admin_user admin_email admin_pass

    domain=$(input_prompt "Domain name (e.g., example.com)" "")
    if [[ -z "$domain" ]]; then
        error "Domain is required!"
        return 1
    fi

    # Generate defaults based on domain
    local domain_safe="${domain//[.-]/_}"
    
    username=$(input_prompt "Linux username" "${domain_safe}")
    db_name=$(input_prompt "Database name" "${domain_safe}_db")
    db_user=$(input_prompt "Database user" "${domain_safe}_user")
    db_pass=$(input_prompt "Database password" "$(generate_password 16)")
    site_title=$(input_prompt "Site title" "My WordPress Site")
    admin_user=$(input_prompt "Admin username" "admin")
    admin_email=$(input_prompt "Admin email" "admin@${domain}")
    admin_pass=$(input_prompt "Admin password" "$(generate_password 16)")

    # Confirm
    echo ""
    echo -e "${YELLOW}Please review the configuration:${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo -e "  Domain:          ${CYAN}${domain}${NC}"
    echo -e "  Username:        ${CYAN}${username}${NC}"
    echo -e "  Database Name:   ${CYAN}${db_name}${NC}"
    echo -e "  Database User:   ${CYAN}${db_user}${NC}"
    echo -e "  Database Pass:   ${CYAN}${db_pass}${NC}"
    echo -e "  Site Title:      ${CYAN}${site_title}${NC}"
    echo -e "  Admin User:      ${CYAN}${admin_user}${NC}"
    echo -e "  Admin Email:     ${CYAN}${admin_email}${NC}"
    echo -e "  Admin Pass:      ${CYAN}${admin_pass}${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""

    if confirm "Proceed with this configuration?"; then
        add_wordpress_site "$domain" "$username" "$db_name" "$db_user" "$db_pass" \
                          "$site_title" "$admin_user" "$admin_email" "$admin_pass"
    else
        warning "Site creation cancelled."
    fi

    echo ""
    read -rp "Press Enter to continue..."
}

handle_caching_menu() {
    local choice
    while true; do
        show_banner
        show_caching_menu
        read -rp "$(echo -e "${CYAN}Pilih opsi [0-3]: ${NC}")" choice

        case $choice in
            1) install_redis ;;
            2) 
                local domain
                domain=$(input_prompt "Domain for WP Super Cache config" "")
                if [[ -n "$domain" ]]; then
                    configure_wsc_nginx "$domain"
                fi
                ;;
            3)
                install_redis
                info "Note: WP Super Cache NGINX config must be done per-site."
                ;;
            0) break ;;
            *) error "Invalid option. Please try again." ;;
        esac

        if [[ "$choice" != "0" ]]; then
            echo ""
            read -rp "Press Enter to continue..."
        fi
    done
}

handle_cron_menu() {
    show_banner
    echo ""
    echo -e "${BOLD}⏰ Setup WordPress Cron${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""

    local username domain
    username=$(input_prompt "Site username" "")
    domain=$(input_prompt "Site domain" "")

    if [[ -n "$username" && -n "$domain" ]]; then
        setup_wp_cron "$username" "$domain"
    else
        error "Username and domain are required!"
    fi

    echo ""
    read -rp "Press Enter to continue..."
}

show_system_info() {
    show_banner
    echo ""
    echo -e "${BOLD}ℹ️  System Information${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    
    echo -e "  ${CYAN}Hostname:${NC}    $(hostname)"
    echo -e "  ${CYAN}OS:${NC}          $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "  ${CYAN}Kernel:${NC}      $(uname -r)"
    echo -e "  ${CYAN}CPU Cores:${NC}   $(nproc)"
    echo -e "  ${CYAN}Memory:${NC}      $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "  ${CYAN}Disk:${NC}        $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')"
    echo -e "  ${CYAN}Uptime:${NC}      $(uptime -p | sed 's/up //')"
    echo ""
    
    echo -e "${BOLD}Installed Services:${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    
    check_service_status "nginx"
    check_service_status "php${PHP_VERSION}-fpm"
    check_service_status "mariadb"
    check_service_status "redis-server"
    check_service_status "ufw"
    check_service_status "fail2ban"
    
    echo ""
    read -rp "Press Enter to continue..."
}

check_service_status() {
    local service="$1"
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} ${service} is ${GREEN}running${NC}"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo -e "  ${YELLOW}○${NC} ${service} is ${YELLOW}stopped${NC}"
        else
            echo -e "  ${DIM}○${NC} ${service} ${DIM}not installed${NC}"
        fi
    fi
}

#===============================================================================
# Full Installation
#===============================================================================

full_installation() {
    show_banner
    echo ""
    echo -e "${BOLD}📦 Full Installation${NC}"
    echo -e "${DIM}─────────────────────────────────────────${NC}"
    echo ""
    warning "This will install and configure:"
    echo "  - Security (Timezone, Updates, UFW, Fail2ban)"
    echo "  - Webserver Stack (NGINX, PHP, MariaDB, Certbot, WP-CLI)"
    echo "  - Redis for Object Caching"
    echo ""

    if ! confirm "Do you want to proceed with full installation?"; then
        return
    fi

    # Security
    info "Step 1/3: Setting up VPS Security..."
    setup_timezone
    update_packages
    install_ufw
    install_fail2ban

    # Webserver Stack
    info "Step 2/3: Installing Webserver Stack..."
    install_nginx
    install_php
    install_mariadb
    install_certbot
    install_wpcli

    # Caching
    info "Step 3/3: Setting up Caching..."
    install_redis

    echo ""
    success "═══════════════════════════════════════════════════════════"
    success "  Full installation completed successfully!"
    success "  You can now add WordPress sites using option 3."
    success "═══════════════════════════════════════════════════════════"
    echo ""
    read -rp "Press Enter to continue..."
}

#===============================================================================
# Main Function
#===============================================================================

main() {
    # Check for command line arguments
    case "${1:-}" in
        --help|-h)
            echo "VPS Setup Script v${VERSION}"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo "  --version, -v  Show version"
            echo ""
            exit 0
            ;;
        --version|-v)
            echo "VPS Setup Script v${VERSION}"
            exit 0
            ;;
    esac

    # Pre-flight checks
    check_root
    check_os

    # Main menu loop
    local choice
    while true; do
        show_banner
        show_main_menu
        read -rp "$(echo -e "${CYAN}Pilih opsi [0-6, i]: ${NC}")" choice

        case $choice in
            1) handle_security_menu ;;
            2) handle_webserver_menu ;;
            3) handle_wordpress_menu ;;
            4) handle_caching_menu ;;
            5) handle_cron_menu ;;
            6) full_installation ;;
            i|I) show_system_info ;;
            0)
                echo ""
                success "Thank you for using VPS Setup Script!"
                echo ""
                exit 0
                ;;
            *)
                error "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Run main function
main "$@"
