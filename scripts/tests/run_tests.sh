#!/bin/bash
#===============================================================================
# Test Runner Script
# Runs all BATS tests for VPS Setup Scripts
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          VPS Setup Scripts - Unit Test Runner             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if BATS is installed
if ! command -v bats &> /dev/null; then
    echo -e "${YELLOW}BATS not found. Installing...${NC}"
    echo ""
    
    # Check OS and install accordingly
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install bats-core
        else
            echo -e "${RED}Please install Homebrew first or install BATS manually${NC}"
            echo "Visit: https://bats-core.readthedocs.io/en/stable/installation.html"
            exit 1
        fi
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y bats
    else
        echo -e "${RED}Please install BATS manually${NC}"
        echo "Visit: https://bats-core.readthedocs.io/en/stable/installation.html"
        exit 1
    fi
fi

echo -e "${GREEN}BATS version: $(bats --version)${NC}"
echo ""

# Run tests
echo -e "${CYAN}Running tests...${NC}"
echo ""

# Track results
FAILED=0
PASSED=0

run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .bats)
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running: ${test_name}${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if bats "$test_file"; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
    echo ""
}

# Run all test files
for test_file in "${SCRIPT_DIR}"/test_*.bats; do
    if [[ -f "$test_file" ]]; then
        run_test_file "$test_file"
    fi
done

# Summary
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                    TEST SUMMARY                          ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}✓ Passed test files: ${PASSED}${NC}"
echo -e "  ${RED}✗ Failed test files: ${FAILED}${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
