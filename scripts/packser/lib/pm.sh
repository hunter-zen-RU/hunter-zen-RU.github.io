#!/usr/bin/env bash
# Package manager operations for packser

# Get list of installed packages from all sources
get_installed_packages() {
    local output_file="$CACHE_DIR/installed_$(date +%Y%m%d).txt"
    > "$output_file"
    
    echo -e "${BOLD}Scanning installed packages...${NC}"
    
    # Native package managers
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        echo -e "${CYAN}[APT]${NC} Scanning..." >&2
        dpkg-query -W -f='${binary:Package}\t${Version}\t${Section}\tinstalled\n' 2>/dev/null >> "$output_file" || true
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " dnf " ]] && [[ "${PM_STATUS[dnf]}" == "ok" ]]; then
        echo -e "${CYAN}[DNF]${NC} Scanning..." >&2
        rpm -qa --queryformat='%{NAME}\t%{VERSION}-%{RELEASE}\t@system\tdnf\n' 2>/dev/null >> "$output_file" || true
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        echo -e "${CYAN}[PACMAN]${NC} Scanning..." >&2
        pacman -Q --queryformat '%n\t%v\t@system\tpacman\n' 2>/dev/null >> "$output_file" || true
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        echo -e "${CYAN}[SNAP]${NC} Scanning..." >&2
        snap list 2>/dev/null | tail -n +2 | awk '{print $1"\t"$2"\t@snap\tsnap"}' >> "$output_file" || true
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        echo -e "${CYAN}[FLATPAK]${NC} Scanning..." >&2
        flatpak list --app --columns=application,version 2>/dev/null | awk -F'\t' '{print $1"\t"$2"\t@flatpak\tflatpak"}' >> "$output_file" || true
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " brew " ]] && [[ "${PM_STATUS[brew]}" == "ok" ]]; then
        echo -e "${CYAN}[BREW]${NC} Scanning..." >&2
        brew list --versions 2>/dev/null | awk '{print $1"\t"$2"\t@brew\tbrew"}' >> "$output_file" || true
    fi
    
    local count=$(wc -l < "$output_file")
    echo -e "${GREEN}✓${NC} Found $count installed packages"
    echo "$output_file"
}

# Update package lists
update_package_lists() {
    echo -e "${BOLD}Updating package lists...${NC}"
    
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        echo -e "  ${CYAN}Updating APT...${NC}"
        sudo apt update 2>&1 | tail -3
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " dnf " ]] && [[ "${PM_STATUS[dnf]}" == "ok" ]]; then
        echo -e "  ${CYAN}Updating DNF...${NC}"
        sudo dnf check-update 2>&1 | tail -3
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        echo -e "  ${CYAN}Updating Pacman...${NC}"
        sudo pacman -Sy 2>&1 | tail -3
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        echo -e "  ${CYAN}Refreshing Snap...${NC}"
        sudo snap refresh --list 2>&1 | tail -3
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        echo -e "  ${CYAN}Updating Flatpak remotes...${NC}"
        flatpak update --appstream 2>&1 | tail -3
    fi
    
    echo -e "${GREEN}✓${NC} Package lists updated"
    read -p "Press Enter to continue..."
}

# Upgrade packages
upgrade_packages() {
    echo -e "${BOLD}Upgrading packages...${NC}"
    
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading APT packages...${NC}"
        sudo apt upgrade
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " dnf " ]] && [[ "${PM_STATUS[dnf]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading DNF packages...${NC}"
        sudo dnf upgrade
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading Pacman packages...${NC}"
        sudo pacman -Syu
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " zypper " ]] && [[ "${PM_STATUS[zypper]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading Zypper packages...${NC}"
        sudo zypper update
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " apk " ]] && [[ "${PM_STATUS[apk]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading APK packages...${NC}"
        sudo apk upgrade
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading Snap packages...${NC}"
        sudo snap refresh
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading Flatpak packages...${NC}"
        flatpak update
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " brew " ]] && [[ "${PM_STATUS[brew]}" == "ok" ]]; then
        echo -e "  ${CYAN}Upgrading Homebrew packages...${NC}"
        brew update && brew upgrade
    fi
    
    echo -e "${GREEN}✓${NC} Upgrade complete"
    read -p "Press Enter to continue..."
}
