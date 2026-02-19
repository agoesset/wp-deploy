#!/bin/bash
#===============================================================================
# SSH Key Management Functions
# Generate and setup SSH keys from server side
#===============================================================================

#===============================================================================
# Generate SSH Key Pair on Server
#===============================================================================
generate_ssh_key() {
    local username="${1:-root}"
    local key_dir
    local key_file
    
    if [[ "$username" == "root" ]]; then
        key_dir="/root/.ssh"
    else
        key_dir="/home/${username}/.ssh"
    fi
    key_file="${key_dir}/id_ed25519"
    
    header "Generate SSH Key for ${username}"
    
    warning "⚠️  SECURITY WARNING ⚠️"
    warning "The private key will be displayed on screen!"
    warning "Make sure no one is watching and you're in a secure environment."
    echo ""
    
    if ! confirm "Are you in a secure environment and want to proceed?"; then
        info "SSH key generation cancelled"
        return 0
    fi
    
    # Check if key already exists
    if [[ -f "$key_file" ]]; then
        warning "SSH key already exists: ${key_file}"
        if ! confirm "Overwrite existing key? (Old key will be lost!)"; then
            info "Keeping existing key"
            return 0
        fi
        backup_file "$key_file"
        backup_file "${key_file}.pub"
    fi
    
    # Create .ssh directory
    step "Creating .ssh directory..."
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    chown "${username}:${username}" "$key_dir" 2>/dev/null || true
    
    # Generate key
    step "Generating ED25519 SSH key pair..."
    local key_comment="${username}@$(hostname)-$(date +%Y%m%d)"
    
    if [[ "$username" == "root" ]]; then
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$key_comment" 2>/dev/null
    else
        sudo -u "$username" ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$key_comment" 2>/dev/null
    fi
    
    if [[ ! -f "$key_file" ]]; then
        error "Failed to generate SSH key"
        return 1
    fi
    
    success "SSH key generated successfully!"
    
    # Setup authorized_keys
    step "Setting up authorized_keys..."
    cat "${key_file}.pub" >> "${key_dir}/authorized_keys"
    chmod 600 "${key_dir}/authorized_keys"
    chown "${username}:${username}" "${key_dir}/authorized_keys" 2>/dev/null || true
    
    # Display public key
    echo ""
    echo -e "${BOLD}📋 Public Key (safe to share):${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    cat "${key_file}.pub"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    echo ""
    info "This public key is already added to authorized_keys"
    
    # Display private key with BIG WARNING
    echo ""
    warning "═══════════════════════════════════════════════════════════"
    warning "  🔐 PRIVATE KEY - COPY THIS SECURELY 🔐"
    warning "  Treat this like a password! Never share!"
    warning "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "${BOLD}🔑 Private Key (COPY THIS TO YOUR LOCAL MACHINE):${NC}"
    echo -e "${RED}${DIM}─────────────────────────────────────────────────────────${NC}"
    cat "$key_file"
    echo -e "${RED}${DIM}─────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Save instructions
    local key_backup="${key_file}.backup-$(date +%Y%m%d-%H%M%S).txt"
    cat > "$key_backup" << EOF
SSH PRIVATE KEY BACKUP FOR ${username}@$(hostname)
Generated: $(date)

=== PRIVATE KEY ===
$(cat "$key_file")

=== PUBLIC KEY ===
$(cat "${key_file}.pub")

=== HOW TO USE ===
1. Copy the private key above (lines between BEGIN/END OPENSSH PRIVATE KEY)
2. Save to your local machine as: ~/.ssh/${username}_$(hostname)
3. Set permissions: chmod 600 ~/.ssh/${username}_$(hostname)
4. Connect with: ssh -i ~/.ssh/${hostname} ${username}@$(curl -s ifconfig.me 2>/dev/null || echo "YOUR-SERVER-IP")

=== SECURITY NOTES ===
- Never share this private key
- Store it in a secure location
- Delete this file after copying: rm ${key_backup}
EOF
    
    chmod 600 "$key_backup"
    
    echo -e "${BOLD}💾 Key also saved to:${NC} ${CYAN}${key_backup}${NC}"
    echo ""
    
    # Instructions
    success "═══════════════════════════════════════════════════════════"
    success "  SSH Key Generated Successfully!"
    success "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "  ${CYAN}Next steps:${NC}"
    echo ""
    echo "  1. Copy the PRIVATE KEY above (red box)"
    echo "  2. On your local machine, create file:"
    echo -e "     ${YELLOW}~/.ssh/${username}_$(hostname)${NC}"
    echo ""
    echo "  3. Paste the private key and save"
    echo ""
    echo "  4. Set permissions:"
    echo -e "     ${YELLOW}chmod 600 ~/.ssh/${username}_$(hostname)${NC}"
    echo ""
    echo "  5. Test connection:"
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR-SERVER-IP")
    echo -e "     ${YELLOW}ssh -i ~/.ssh/${username}_$(hostname) ${username}@${server_ip}${NC}"
    echo ""
    echo -e "  ${CYAN}After confirming key works, run SSH hardening:${NC}"
    echo -e "     ${YELLOW}Menu 1 → 6 (Harden SSH)${NC}"
    echo ""
    warning "Delete ${key_backup} after copying the key!"
    
    # Option to delete backup now
    if confirm "Delete backup file now? (Only if you've copied the key)"; then
        rm -f "$key_backup"
        info "Backup file deleted"
    else
        warning "Backup file kept at: ${key_backup}"
        info "Remember to delete it after copying the key!"
    fi
}

#===============================================================================
# Import SSH Public Key
#===============================================================================
import_ssh_pubkey() {
    local username="${1:-root}"
    local key_dir
    
    if [[ "$username" == "root" ]]; then
        key_dir="/root/.ssh"
    else
        key_dir="/home/${username}/.ssh"
    fi
    
    header "Import SSH Public Key for ${username}"
    
    echo "Paste your SSH PUBLIC KEY below (from ~/.ssh/id_*.pub on your local machine)"
    echo "It should look like: ssh-ed25519 AAAAC3NzaC... comment"
    echo ""
    
    local pubkey
    read -rp "$(echo -e "${CYAN}Public key: ${NC}")" pubkey
    
    if [[ -z "$pubkey" ]]; then
        error "No key provided"
        return 1
    fi
    
    # Basic validation
    if [[ ! "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ssh-dss)\  ]]; then
        error "Invalid public key format"
        error "Key should start with: ssh-ed25519, ssh-rsa, ecdsa-sha2-nistp256, or ssh-dss"
        return 1
    fi
    
    # Create .ssh directory
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    chown "${username}:${username}" "$key_dir" 2>/dev/null || true
    
    # Add to authorized_keys
    echo "$pubkey" >> "${key_dir}/authorized_keys"
    chmod 600 "${key_dir}/authorized_keys"
    chown "${username}:${username}" "${key_dir}/authorized_keys" 2>/dev/null || true
    
    success "Public key imported successfully!"
    info "You can now login with: ssh ${username}@$(curl -s ifconfig.me 2>/dev/null || echo "SERVER-IP")"
    
    # Show current keys
    echo ""
    info "Current authorized keys for ${username}:"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    wc -l < "${key_dir}/authorized_keys" | xargs echo "Total keys:"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
}

#===============================================================================
# List SSH Keys
#===============================================================================
list_ssh_keys() {
    local username="${1:-root}"
    local key_dir
    
    if [[ "$username" == "root" ]]; then
        key_dir="/root/.ssh"
    else
        key_dir="/home/${username}/.ssh"
    fi
    
    header "SSH Keys for ${username}"
    
    if [[ ! -d "$key_dir" ]]; then
        info "No .ssh directory found for ${username}"
        return 0
    fi
    
    echo -e "${BOLD}Private Keys:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    for key in "$key_dir"/id_*; do
        if [[ -f "$key" ]] && [[ ! "$key" =~ \.pub$ ]]; then
            local key_type
            key_type=$(ssh-keygen -l -f "$key" 2>/dev/null | awk '{print $2}' || echo "unknown")
            local key_size
            key_size=$(ssh-keygen -l -f "$key" 2>/dev/null | awk '{print $1}' || echo "?")
            local key_date
            key_date=$(stat -c %y "$key" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            
            echo -e "  ${CYAN}$(basename "$key")${NC}"
            echo -e "    Type: ${key_type}, Size: ${key_size} bits"
            echo -e "    Created: ${key_date}"
            echo ""
        fi
    done
    
    echo -e "${BOLD}Authorized Keys:${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
    if [[ -f "${key_dir}/authorized_keys" ]]; then
        local key_count
        key_count=$(wc -l < "${key_dir}/authorized_keys")
        echo "  Total authorized keys: ${key_count}"
        echo ""
        
        # Show fingerprint of each key
        local i=1
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local fp
                fp=$(echo "$line" | ssh-keygen -l -f /dev/stdin 2>/dev/null | awk '{print $2}' || echo "invalid")
                local comment
                comment=$(echo "$line" | awk '{print $3}')
                echo -e "  ${i}. ${fp} ${comment:+($comment)}"
                ((i++))
            fi
        done < "${key_dir}/authorized_keys"
    else
        echo "  No authorized_keys file"
    fi
    echo ""
}

#===============================================================================
# Remove SSH Key
#===============================================================================
remove_ssh_key() {
    local username="${1:-root}"
    local key_dir
    
    if [[ "$username" == "root" ]]; then
        key_dir="/root/.ssh"
    else
        key_dir="/home/${username}/.ssh"
    fi
    
    header "Remove SSH Key for ${username}"
    
    list_ssh_keys "$username"
    
    echo ""
    echo -e "${YELLOW}Which key to remove?${NC}"
    echo "  1. Remove private key file"
    echo "  2. Remove authorized key (public key entry)"
    echo "  0. Cancel"
    echo ""
    
    local choice
    read -rp "$(echo -e "${CYAN}Choice [0-2]: ${NC}")" choice
    
    case $choice in
        1)
            echo ""
            ls -1 "$key_dir"/id_* 2>/dev/null | grep -v '\.pub$' || echo "No private keys found"
            echo ""
            local key_name
            read -rp "$(echo -e "${CYAN}Key filename to remove: ${NC}")" key_name
            
            if [[ -f "${key_dir}/${key_name}" ]]; then
                if confirm "Remove ${key_name}? This cannot be undone!"; then
                    rm -f "${key_dir}/${key_name}" "${key_dir}/${key_name}.pub"
                    success "Key removed"
                fi
            else
                error "Key not found"
            fi
            ;;
        2)
            if [[ -f "${key_dir}/authorized_keys" ]]; then
                echo ""
                cat -n "${key_dir}/authorized_keys"
                echo ""
                local line_num
                read -rp "$(echo -e "${CYAN}Line number to remove: ${NC}")" line_num
                
                if [[ "$line_num" =~ ^[0-9]+$ ]]; then
                    sed -i "${line_num}d" "${key_dir}/authorized_keys"
                    success "Key entry removed from authorized_keys"
                else
                    error "Invalid line number"
                fi
            fi
            ;;
        0)
            info "Cancelled"
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
}

#===============================================================================
# SSH Key Management Menu
#===============================================================================
handle_ssh_key_menu() {
    while true; do
        show_banner
        echo ""
        echo -e "${BOLD}🔑 SSH Key Management${NC}"
        echo -e "${DIM}─────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC} Generate New SSH Key Pair"
        echo -e "  ${GREEN}2.${NC} Import Public Key (from local machine)"
        echo -e "  ${GREEN}3.${NC} List Existing Keys"
        echo -e "  ${GREEN}4.${NC} Remove SSH Key"
        echo ""
        echo -e "  ${RED}0.${NC} Back to Main Menu"
        echo ""
        echo -e "${DIM}─────────────────────────────────────────${NC}"
        
        local choice
        read -rp "$(echo -e "${CYAN}Pilih opsi [0-4]: ${NC}")" choice
        
        case $choice in
            1) generate_ssh_key ;;
            2) import_ssh_pubkey ;;
            3) list_ssh_keys ;;
            4) remove_ssh_key ;;
            0) break ;;
            *) error "Invalid option" ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            echo ""
            read -rp "Press Enter to continue..."
        fi
    done
}
