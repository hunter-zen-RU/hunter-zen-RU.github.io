#!/usr/bin/env bash
# Utility functions for packser

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Running as root${NC}"
        return 0
    else
        return 1
    fi
}

# Check dependencies
check_deps() {
    local deps=("curl" "wget")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing optional dependencies: ${missing[*]}${NC}"
    fi
}

# Create backup
create_backup() {
    local backup_file="$CACHE_DIR/packser_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo -e "Creating backup at $backup_file"
    # Backup logic here
}
