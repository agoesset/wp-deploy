#!/bin/bash
#===============================================================================
# Helper Functions Library
#===============================================================================

#===============================================================================
# Check if running as root
#===============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        echo ""
        echo "Please run: sudo $0"
        exit 1
    fi
}

#===============================================================================
# Check OS Compatibility
#===============================================================================
check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                info "Detected OS: $PRETTY_NAME"
                ;;
            *)
                warning "This script is designed for Ubuntu/Debian. Your OS: $PRETTY_NAME"
                if ! confirm "Do you want to continue anyway?"; then
                    exit 1
                fi
                ;;
        esac
    else
        warning "Cannot detect OS. This script is designed for Ubuntu/Debian."
        if ! confirm "Do you want to continue anyway?"; then
            exit 1
        fi
    fi
}

#===============================================================================
# Check if a command exists
#===============================================================================
check_command() {
    command -v "$1" &>/dev/null
}

#===============================================================================
# Confirmation prompt
#===============================================================================
confirm() {
    local message="${1:-Are you sure?}"
    local response

    echo -ne "${YELLOW}${message}${NC} [y/N]: "
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#===============================================================================
# Input prompt with default value
#===============================================================================
input_prompt() {
    local message="$1"
    local default="$2"
    local response

    # Use /dev/tty for prompt display to avoid capture by subshell
    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}${message}${NC} [${DIM}${default}${NC}]: " >/dev/tty
    else
        echo -ne "${CYAN}${message}${NC}: " >/dev/tty
    fi

    read -r response </dev/tty

    if [[ -z "$response" ]]; then
        echo "$default"
    else
        echo "$response"
    fi
}

#===============================================================================
# Password input (hidden)
#===============================================================================
password_prompt() {
    local message="$1"
    local password

    echo -ne "${CYAN}${message}${NC}: "
    read -rs password
    echo ""

    echo "$password"
}

#===============================================================================
# Generate random password
#===============================================================================
generate_password() {
    local length="${1:-16}"
    # Use LC_ALL=C to handle binary data properly
    # Generate password with letters, numbers, and some special chars
    LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c "$length"
}

#===============================================================================
# Generate random string (alphanumeric only)
#===============================================================================
generate_random_string() {
    local length="${1:-12}"
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

#===============================================================================
# Wait for apt lock
#===============================================================================
wait_for_apt() {
    local timeout=300
    local waited=0

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        
        if [[ $waited -eq 0 ]]; then
            warning "Waiting for other apt processes to finish..."
        fi
        
        sleep 5
        waited=$((waited + 5))
        
        if [[ $waited -ge $timeout ]]; then
            error "Timeout waiting for apt lock"
            return 1
        fi
    done
}

#===============================================================================
# Run apt command with lock handling
#===============================================================================
apt_install() {
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

#===============================================================================
# Check if service is running
#===============================================================================
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

#===============================================================================
# Restart service safely
#===============================================================================
restart_service() {
    local service="$1"
    
    info "Restarting ${service}..."
    
    if systemctl restart "$service"; then
        success "${service} restarted successfully"
        return 0
    else
        error "Failed to restart ${service}"
        return 1
    fi
}

#===============================================================================
# Enable and start service
#===============================================================================
enable_service() {
    local service="$1"
    
    systemctl enable "$service" 2>/dev/null
    systemctl start "$service" 2>/dev/null
    
    if is_service_running "$service"; then
        success "${service} is running"
        return 0
    else
        error "Failed to start ${service}"
        return 1
    fi
}

#===============================================================================
# Backup file before modification
#===============================================================================
backup_file() {
    local file="$1"
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    
    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
        info "Backed up ${file} to ${backup}"
    fi
}

#===============================================================================
# Sanitize string for use as username/database name
#===============================================================================
sanitize_name() {
    local input="$1"
    # Replace dots and dashes with underscores, remove other special chars
    echo "$input" | sed 's/[.-]/_/g' | sed 's/[^a-zA-Z0-9_]//g' | tr '[:upper:]' '[:lower:]'
}

#===============================================================================
# Validate domain name
#===============================================================================
validate_domain() {
    local domain="$1"
    
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Check if port is open
#===============================================================================
is_port_open() {
    local port="$1"
    netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "
}

#===============================================================================
# Get public IP
#===============================================================================
get_public_ip() {
    curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "unknown"
}

#===============================================================================
# Create directory if not exists
#===============================================================================
ensure_dir() {
    local dir="$1"
    local owner="${2:-}"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        info "Created directory: ${dir}"
    fi
    
    if [[ -n "$owner" ]]; then
        chown -R "$owner:$owner" "$dir"
    fi
}
