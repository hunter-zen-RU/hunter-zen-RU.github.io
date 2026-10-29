#!/usr/bin/env bash
# UI/Dashboard for packser

show_dashboard() {
    clear
    print_header
    
    # System Info Bar
    echo -e "${BOLD}System:${NC} $DISTRO_NAME | ${BOLD}Arch:${NC} $ARCH | ${BOLD}Init:${NC} $INIT"
    echo -e "${BOLD}Package Managers:${NC} ${#PM_LIST[@]} detected"
    echo ""
    
    # Status summary
    local ok_count=0 err_count=0
    for pm in "${PM_LIST[@]}"; do
        if [[ "${PM_STATUS[$pm]:-ok}" == "ok" ]]; then
            ok_count=$((ok_count + 1))
        else
            err_count=$((err_count + 1))
        fi
    done
    
    echo -e "${GREEN}●${NC} Working: $ok_count  ${RED}●${NC} Issues: $err_count"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Menu options
    echo -e "${BOLD}${WHITE}MAIN MENU${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${BOLD}Browse Packages${NC} - Browse by category"
    echo -e "  ${GREEN}2)${NC} ${BOLD}Search Packages${NC} - Search with filters (fzf/arrow)"
    echo -e "  ${GREEN}3)${NC} ${BOLD}Installed Packages${NC} - View all installed"
    echo -e "  ${GREEN}4)${NC} ${BOLD}Update Package Lists${NC} - Sync repositories"
    echo -e "  ${GREEN}5)${NC} ${BOLD}Upgrade All Packages${NC} - Update from all sources"
    echo -e "  ${GREEN}6)${NC} ${BOLD}Package Manager Status${NC} - Health & diagnostics"
    echo -e "  ${GREEN}7)${NC} ${BOLD}Mark & Apply${NC} - Mark packages for batch ops"
    echo -e "  ${GREEN}8)${NC} ${BOLD}Package Database${NC} - Browse curated packages"
    echo -e "  ${GREEN}9)${NC} ${BOLD}Settings${NC} - Configure packser"
    echo -e "  ${RED}0)${NC} ${BOLD}Exit${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "$(echo -e ${BOLD}Enter your choice [0-9]:${NC} )" choice
    
    case $choice in
        1) browse_by_category ;;
        2) search_menu ;;
        3) view_installed ;;
        4) update_package_lists; show_dashboard ;;
        5) upgrade_packages; show_dashboard ;;
        6) show_pm_status; show_dashboard ;;
        7) mark_manage_menu; show_dashboard ;;
        8) browse_database; show_dashboard ;;
        9) settings_menu; show_dashboard ;;
        0) clear; echo -e "${CYAN}Thanks for using packser v${VERSION}!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 2; show_dashboard ;;
    esac
}

browse_by_category() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Browse Packages by Category${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "  ${GREEN}1)${NC} ${BOLD}🖥️  System Tools${NC}"
    echo -e "  ${GREEN}2)${NC} ${BOLD}🌐 Network & Internet${NC}"
    echo -e "  ${GREEN}3)${NC} ${BOLD}🎨 Multimedia${NC}"
    echo -e "  ${GREEN}4)${NC} ${BOLD}💻 Development${NC}"
    echo -e "  ${GREEN}5)${NC} ${BOLD}🗂️  Utilities & Accessories${NC}"
    echo -e "  ${GREEN}6)${NC} ${BOLD}🎮 Games${NC}"
    echo -e "  ${GREEN}7)${NC} ${BOLD}📚 Education & Science${NC}"
    echo -e "  ${GREEN}8)${NC} ${BOLD}🔒 Security & Privacy${NC}"
    echo -e "  ${GREEN}9)${NC} ${BOLD}📦 All Packages${NC}"
    echo -e "  ${YELLOW}b)${NC} Back to Dashboard"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "$(echo -e ${BOLD}Enter choice:${NC} )" cat_choice
    
    case $cat_choice in
        1) show_category "system" ;;
        2) show_category "network" ;;
        3) show_category "multimedia" ;;
        4) show_category "dev" ;;
        5) show_category "utils" ;;
        6) show_category "games" ;;
        7) show_category "edu" ;;
        8) show_category "security" ;;
        9) show_category "all" ;;
        b|B) show_dashboard ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 2; browse_by_category ;;
    esac
}

show_category() {
    local category="$1"
    clear
    print_header
    echo -e "${BOLD}${CYAN}Category: $(echo $category | tr '[:lower:]' '[:upper:]')${NC}"
    echo ""
    
    # Check if whiptail is available for better UI
    if command -v whiptail >/dev/null 2>&1; then
        local packages=()
        case $category in
            system) packages=("htop" "btop" "neofetch" "tree" "ncdu") ;;
            network) packages=("curl" "wget" "firefox" "chromium" "nmap") ;;
            multimedia) packages=("vlc" "mpv" "ffmpeg" "obs-studio" "audacity") ;;
            dev) packages=("git" "vim" "neovim" "gcc" "nodejs" "python3" "docker") ;;
            utils) packages=("rsync" "zip" "unzip" "tmux" "ranger") ;;
            games) packages=("steam" "lutris" "0ad") ;;
            edu) packages=("anki" "kalgebra") ;;
            security) packages=("ufw" "fail2ban" "gpg") ;;
            all) packages=("htop" "git" "vim" "curl" "firefox" "vlc" "docker" "nodejs") ;;
        esac
        
        local menu_items=()
        for pkg in "${packages[@]}"; do
            menu_items+=("$pkg" "Available from multiple sources")
        done
        
        whiptail --title "Packages - $category" --menu "Select a package to install/manage:" 20 70 10 "${menu_items[@]}" 3>&1 1>&2 2>&3
    else
        echo -e "Sample packages in this category:"
        echo "  - Package suggestions coming soon"
        echo ""
        read -p "Press Enter to go back..."
    fi
    
    browse_by_category
}

search_menu() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Search Packages${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "$(echo -e ${BOLD}Enter search term:${NC} )" search_term
    
    if [ -z "$search_term" ]; then
        echo -e "${RED}No search term provided${NC}"
        sleep 2
        show_dashboard
        return
    fi
    
    echo ""
    echo -e "${BOLD}Search filters:${NC}"
    echo "  1) All sources"
    echo "  2) Native packages only"
    echo "  3) Snap only"
    echo "  4) Flatpak only"
    echo ""
    read -p "Filter [1-4]: " filter
    
    search_packages "$search_term" "$filter"
    
    echo ""
    read -p "Press Enter to return to dashboard..."
    show_dashboard
}

search_packages() {
    local term="$1"
    local filter="$2"
    
    echo -e "\n${BOLD}Searching for: ${CYAN}$term${NC}\n"
    
    if [[ " ${PM_LIST[*]} " =~ " apt " ]] && [[ "${PM_STATUS[apt]}" == "ok" ]] && [[ "$filter" != "3" && "$filter" != "4" ]]; then
        echo -e "${CYAN}[APT]${NC}"
        apt search "^$term" 2>&1 | grep -B1 -A2 "^$term/" | head -15
        echo ""
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " snap " ]] && [[ "${PM_STATUS[snap]}" == "ok" ]] && [[ "$filter" != "2" && "$filter" != "4" ]]; then
        echo -e "${CYAN}[SNAP]${NC}"
        snap find "$term" 2>&1 | head -10
        echo ""
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " flatpak " ]] && [[ "${PM_STATUS[flatpak]}" == "ok" ]] && [[ "$filter" != "2" && "$filter" != "3" ]]; then
        echo -e "${CYAN}[FLATPAK]${NC}"
        flatpak search "$term" 2>&1 | head -10
        echo ""
    fi
    
    if [[ " ${PM_LIST[*]} " =~ " pacman " ]] && [[ "${PM_STATUS[pacman]}" == "ok" ]] && [[ "$filter" != "3" && "$filter" != "4" ]]; then
        echo -e "${CYAN}[PACMAN]${NC}"
        pacman -Ss "$term" 2>&1 | head -10
        echo ""
    fi
}

view_installed() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Installed Packages${NC}"
    echo ""
    
    local inst_file=$(get_installed_packages)
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if command -v less >/dev/null 2>&1; then
        cat "$inst_file" | column -t -s$'\t' | less
    else
        cat "$inst_file" | column -t -s$'\t' | head -100
        echo ""
        echo -e "${YELLOW}Showing first 100. Full list in: $inst_file${NC}"
    fi
    
    show_dashboard
}

show_pm_status() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Package Manager Status & Health Check${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    for pm in "${PM_LIST[@]}"; do
        echo -e "${BOLD}[$pm]${NC}"
        if [[ "${PM_STATUS[$pm]:-ok}" == "ok" ]]; then
            echo -e "  Status: ${GREEN}● Operational${NC}"
            echo -e "  Path: ${PM_PATH[$pm]:-N/A}"
            # Try a quick health check
            case $pm in
                apt) apt --version | head -1 ;;
                snap) snap version | head -2 ;;
                flatpak) flatpak --version ;;
                pacman) pacman --version | head -1 ;;
                dnf) dnf --version | head -1 ;;
            esac
        else
            echo -e "  Status: ${RED}● Issues Detected${NC}"
            echo -e "  ${YELLOW}Recommendation: Check configuration and permissions${NC}"
        fi
        echo ""
    done
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Press Enter to return to dashboard..."
}

mark_manage_menu() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Mark & Manage Packages${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    list_marked
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "  ${GREEN}1)${NC} Mark package for install"
    echo -e "  ${GREEN}2)${NC} Mark package for removal"
    echo -e "  ${GREEN}3)${NC} Mark package for update"
    echo -e "  ${GREEN}4)${NC} Unmark package"
    echo -e "  ${GREEN}5)${NC} Apply all marked operations"
    echo -e "  ${GREEN}6)${NC} Clear all marks"
    echo -e "  ${YELLOW}b)${NC} Back to Dashboard"
    echo ""
    
    read -p "$(echo -e ${BOLD}Enter choice:${NC} )" mchoice
    
    case $mchoice in
        1)
            read -p "Package name to mark for install: " pkg
            [ -n "$pkg" ] && mark_package "$pkg" "install"
            sleep 2
            mark_manage_menu
            ;;
        2)
            read -p "Package name to mark for removal: " pkg
            [ -n "$pkg" ] && mark_package "$pkg" "remove"
            sleep 2
            mark_manage_menu
            ;;
        3)
            read -p "Package name to mark for update: " pkg
            [ -n "$pkg" ] && mark_package "$pkg" "update"
            sleep 2
            mark_manage_menu
            ;;
        4)
            read -p "Package name to unmark: " pkg
            [ -n "$pkg" ] && unmark_package "$pkg"
            sleep 2
            mark_manage_menu
            ;;
        5)
            apply_marked
            ;;
        6)
            > "$MARK_FILE"
            echo -e "${GREEN}✓${NC} All marks cleared"
            sleep 2
            mark_manage_menu
            ;;
        b|B) return ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 2; mark_manage_menu ;;
    esac
}

browse_database() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Package Database${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    generate_package_db >/dev/null 2>&1
    
    echo -e "  ${GREEN}1)${NC} Browse all packages"
    echo -e "  ${GREEN}2)${NC} Browse by category"
    echo -e "  ${GREEN}3)${NC} Search database"
    echo -e "  ${YELLOW}b)${NC} Back"
    echo ""
    
    read -p "$(echo -e ${BOLD}Enter choice:${NC} )" dbchoice
    
    case $dbchoice in
        1)
            clear
            print_header
            echo -e "${BOLD}All Packages from Database${NC}"
            echo ""
            db_search "." "all" | column -t -s'|' | head -80
            echo ""
            read -p "Press Enter to continue..."
            browse_database
            ;;
        2)
            local cats=("system" "network" "dev" "multimedia" "games" "security" "utils" "all")
            local sel=$(navigate_menu "Select Category" "${cats[@]}")
            if [ -n "$sel" ] && [ "$sel" != "" ]; then
                clear
                print_header
                echo -e "${BOLD}Category: $sel${NC}"
                echo ""
                db_search "." "$sel" | column -t -s'|' 
                echo ""
                read -p "Press Enter to continue..."
            fi
            browse_database
            ;;
        3)
            read -p "Search term: " st
            if [ -n "$st" ]; then
                clear
                print_header
                echo -e "${BOLD}Search Results for: $st${NC}"
                echo ""
                db_search "$st" "all" | column -t -s'|' 
                echo ""
                read -p "Press Enter to continue..."
            fi
            browse_database
            ;;
        b|B) return ;;
        *) echo -e "${RED}Invalid choice${NC}"; sleep 2; browse_database ;;
    esac
}

settings_menu() {
    clear
    print_header
    echo -e "${BOLD}${CYAN}Settings${NC}"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Version:${NC} packser v$VERSION"
    echo -e "  ${BOLD}Script Directory:${NC} $SCRIPT_DIR"
    echo -e "  ${BOLD}Config Directory:${NC} $CONFIG_DIR"
    echo -e "  ${BOLD}Cache Directory:${NC} $CACHE_DIR"
    echo -e "  ${BOLD}Data Directory:${NC} $DATA_DIR"
    echo ""
    echo -e "${CYAN}Tools:${NC}"
    command -v fzf >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} fzf (enhanced navigation)" || echo -e "  ${GRAY}○${NC} fzf (not installed)"
    command -v gum >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} gum (modern UI)" || echo -e "  ${GRAY}○${NC} gum (not installed)"
    command -v whiptail >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} whiptail" || echo -e "  ${GRAY}○${NC} whiptail"
    command -v dialog >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} dialog" || echo -e "  ${GRAY}○${NC} dialog"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Press Enter to return to dashboard..."
}
