#!/bin/bash
#===============================================================================
# Colors and Output Formatting Library
#===============================================================================

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# Bold Colors
export BOLD='\033[1m'
export DIM='\033[2m'

# Reset
export NC='\033[0m'

# Symbols
export CHECK_MARK="✓"
export CROSS_MARK="✗"
export ARROW="→"
export BULLET="•"

#===============================================================================
# Output Functions
#===============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO" "$1"
}

success() {
    echo -e "${GREEN}[${CHECK_MARK}]${NC} $1"
    log "SUCCESS" "$1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING" "$1"
}

error() {
    echo -e "${RED}[${CROSS_MARK}]${NC} $1" >&2
    log "ERROR" "$1"
}

step() {
    echo -e "${PURPLE}${ARROW}${NC} $1"
    log "STEP" "$1"
}

#===============================================================================
# Logging Function
#===============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only log if LOG_FILE is writable
    if [[ -w "$(dirname "${LOG_FILE:-/var/log/vps-setup.log}")" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE:-/var/log/vps-setup.log}"
    fi
}

#===============================================================================
# Spinner for long operations
#===============================================================================

spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spin='-\|/'
    local i=0

    echo -ne "${CYAN}${message}${NC} "
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        echo -ne "\b${spin:$i:1}"
        sleep 0.1
    done
    echo -ne "\b \n"
}

#===============================================================================
# Progress Bar
#===============================================================================

progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r${CYAN}[${NC}"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "${CYAN}]${NC} ${percentage}%%"
}

#===============================================================================
# Divider
#===============================================================================

divider() {
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
}

header() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    divider
}
