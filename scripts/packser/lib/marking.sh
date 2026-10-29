#!/usr/bin/env bash
# Package marking and batch operations

MARK_FILE="$CACHE_DIR/marked_packages.list"

mark_package() {
    local pkg="$1"
    local action="$2" # install, remove, update
    
    touch "$MARK_FILE"
    if grep -q "^$pkg|" "$MARK_FILE"; then
        # Update existing
        sed -i "s|^$pkg|.*|$pkg|$action|$(date +%s)|" "$MARK_FILE"
    else
        echo "$pkg|$action|$(date +%s)" >> "$MARK_FILE"
    fi
    echo -e "${GREEN}✓${NC} Marked $pkg for $action"
}

unmark_package() {
    local pkg="$1"
    touch "$MARK_FILE"
    sed -i "/^$pkg|/d" "$MARK_FILE"
    echo -e "${YELLOW}○${NC} Unmarked $pkg"
}

list_marked() {
    touch "$MARK_FILE"
    if [ ! -s "$MARK_FILE" ]; then
        echo -e "${GRAY}No packages marked${NC}"
        return
    fi
    
    echo -e "${BOLD}Marked Packages:${NC}"
    echo ""
    while IFS='|' read -r pkg action timestamp; do
        case $action in
            install) echo -e "  ${GREEN}+${NC} $pkg - Install" ;;
            remove) echo -e "  ${RED}-${NC} $pkg - Remove" ;;
            update) echo -e "  ${BLUE}↑${NC} $pkg - Update" ;;
            *) echo -e "  ${GRAY}•${NC} $pkg - $action" ;;
        esac
    done < "$MARK_FILE"
}

apply_marked() {
    touch "$MARK_FILE"
    if [ ! -s "$MARK_FILE" ]; then
        echo -e "${YELLOW}No packages marked for operation${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    clear
    print_header
    echo -e "${BOLD}${CYAN}Apply Marked Packages${NC}"
    echo ""
    list_marked
    echo ""
    echo -e "${RED}⚠ This will perform the marked actions${NC}"
    echo ""
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        sleep 2
        return
    fi
    
    while IFS='|' read -r pkg action timestamp; do
        echo -e "\n${BOLD}Processing: $pkg ($action)${NC}"
        case $action in
            install)
                install_package "$pkg"
                ;;
            remove)
                remove_package "$pkg"
                ;;
            update)
                update_package "$pkg"
                ;;
        esac
    done < "$MARK_FILE"
    
    # Clear marked list after applying
    > "$MARK_FILE"
    echo -e "\n${GREEN}✓${NC} All marked operations completed"
    read -p "Press Enter to continue..."
}

install_package() {
    local pkg="$1"
    echo -e "  Installing $pkg..."
    
    # Try to determine best source
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        sudo apt install -y "$pkg" 2>&1 | tail -5
    elif [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        sudo pacman -S --noconfirm "$pkg" 2>&1 | tail -5
    elif [[ " ${PM_LIST[*]} " =~ " dnf " ]] && [[ "${PM_STATUS[dnf]}" == "ok" ]]; then
        sudo dnf install -y "$pkg" 2>&1 | tail -5
    elif [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        sudo snap install "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        flatpak install -y flathub "$pkg" 2>&1 | tail -3
    else
        echo -e "  ${RED}✗${NC} No suitable package manager found"
    fi
}

remove_package() {
    local pkg="$1"
    echo -e "  Removing $pkg..."
    
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        sudo apt remove -y "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        sudo pacman -R --noconfirm "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " dnf " ]] && [[ "${PM_STATUS[dnf]}" == "ok" ]]; then
        sudo dnf remove -y "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        sudo snap remove "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        flatpak uninstall -y "$pkg" 2>&1 | tail -3
    else
        echo -e "  ${RED}✗${NC} No suitable package manager found"
    fi
}

update_package() {
    local pkg="$1"
    echo -e "  Updating $pkg..."
    # Use upgrade/refresh
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]]; then
        sudo apt install --only-upgrade -y "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]]; then
        sudo pacman -S --noconfirm "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]]; then
        sudo snap refresh "$pkg" 2>&1 | tail -3
    elif [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]]; then
        flatpak update -y "$pkg" 2>&1 | tail -3
    fi
}
