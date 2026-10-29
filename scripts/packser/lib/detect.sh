#!/usr/bin/env bash
# System detection for packser

# Package manager state is initialized here and filled by check_managers().
# It must stay global: the dashboard and other menus read it after detection.
declare -a PM_LIST=()
declare -A PM_STATUS=()
declare -A PM_PATH=()

detect_system() {
    echo -e "${BOLD}🔍 Detecting System...${NC}"
    
    # Detect OS. Source os-release in a subshell so it cannot overwrite
    # packser's own variables (for example VERSION).
    if [ -f /etc/os-release ]; then
        DISTRO_NAME="$(. /etc/os-release; printf '%s' "${NAME:-}")"
        DISTRO_ID="$(. /etc/os-release; printf '%s' "${ID:-}")"
        DISTRO_VERSION="$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")"
        echo -e "  ${GREEN}✓${NC} OS: $DISTRO_NAME ($DISTRO_ID)"
    elif [ -f /etc/lsb-release ]; then
        DISTRO_NAME="$(. /etc/lsb-release; printf '%s' "${DISTRIB_DESCRIPTION:-}")"
        DISTRO_ID="$(. /etc/lsb-release; printf '%s' "${DISTRIB_ID:-}")"
        echo -e "  ${GREEN}✓${NC} OS: $DISTRO_NAME"
    else
        DISTRO_NAME="$(uname -s)"
        DISTRO_ID="unknown"
        echo -e "  ${GREEN}✓${NC} OS: $DISTRO_NAME"
    fi
    
    # Detect architecture
    ARCH="$(uname -m)"
    echo -e "  ${GREEN}✓${NC} Architecture: $ARCH"
    
    # Detect init system
    if command -v systemctl >/dev/null 2>&1; then
        INIT="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT="openrc"
    else
        INIT="unknown"
    fi
    echo -e "  ${GREEN}✓${NC} Init: $INIT"
    
    echo ""
}

check_managers() {
    echo -e "${BOLD}📦 Detecting Package Managers...${NC}"
    
    PM_LIST=()
    PM_STATUS=()
    PM_PATH=()
    
    # APT (Debian/Ubuntu)
    if command -v apt >/dev/null 2>&1; then
        PM_LIST+=("apt")
        PM_PATH["apt"]="$(command -v apt)"
        if apt --version >/dev/null 2>&1; then
            PM_STATUS["apt"]="ok"
            echo -e "  ${GREEN}✓${NC} APT (Debian/Ubuntu) - Available"
        else
            PM_STATUS["apt"]="error"
            echo -e "  ${RED}✗${NC} APT - Issues detected"
        fi
    fi
    
    # DNF (Fedora/RHEL)
    if command -v dnf >/dev/null 2>&1; then
        PM_LIST+=("dnf")
        PM_PATH["dnf"]="$(command -v dnf)"
        if dnf --version >/dev/null 2>&1; then
            PM_STATUS["dnf"]="ok"
            echo -e "  ${GREEN}✓${NC} DNF (Fedora/RHEL) - Available"
        else
            PM_STATUS["dnf"]="error"
            echo -e "  ${RED}✗${NC} DNF - Issues detected"
        fi
    fi
    
    # YUM
    if command -v yum >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1; then
        PM_LIST+=("yum")
        PM_PATH["yum"]="$(command -v yum)"
        if yum --version >/dev/null 2>&1; then
            PM_STATUS["yum"]="ok"
            echo -e "  ${GREEN}✓${NC} YUM (RHEL/CentOS) - Available"
        else
            PM_STATUS["yum"]="error"
            echo -e "  ${RED}✗${NC} YUM - Issues detected"
        fi
    fi
    
    # Pacman (Arch)
    if command -v pacman >/dev/null 2>&1; then
        PM_LIST+=("pacman")
        PM_PATH["pacman"]="$(command -v pacman)"
        if pacman --version >/dev/null 2>&1; then
            PM_STATUS["pacman"]="ok"
            echo -e "  ${GREEN}✓${NC} Pacman (Arch Linux) - Available"
        else
            PM_STATUS["pacman"]="error"
            echo -e "  ${RED}✗${NC} Pacman - Issues detected"
        fi
    fi
    
    # Zypper (openSUSE)
    if command -v zypper >/dev/null 2>&1; then
        PM_LIST+=("zypper")
        PM_PATH["zypper"]="$(command -v zypper)"
        if zypper --version >/dev/null 2>&1; then
            PM_STATUS["zypper"]="ok"
            echo -e "  ${GREEN}✓${NC} Zypper (openSUSE) - Available"
        else
            PM_STATUS["zypper"]="error"
            echo -e "  ${RED}✗${NC} Zypper - Issues detected"
        fi
    fi
    
    # APK (Alpine)
    if command -v apk >/dev/null 2>&1; then
        PM_LIST+=("apk")
        PM_PATH["apk"]="$(command -v apk)"
        if apk --version >/dev/null 2>&1; then
            PM_STATUS["apk"]="ok"
            echo -e "  ${GREEN}✓${NC} APK (Alpine Linux) - Available"
        else
            PM_STATUS["apk"]="error"
            echo -e "  ${RED}✗${NC} APK - Issues detected"
        fi
    fi
    
    # Emerge (Gentoo)
    if command -v emerge >/dev/null 2>&1; then
        PM_LIST+=("emerge")
        PM_PATH["emerge"]="$(command -v emerge)"
        if emerge --version >/dev/null 2>&1; then
            PM_STATUS["emerge"]="ok"
            echo -e "  ${GREEN}✓${NC} Portage/Emerge (Gentoo) - Available"
        else
            PM_STATUS["emerge"]="error"
            echo -e "  ${RED}✗${NC} Portage/Emerge - Issues detected"
        fi
    fi
    
    # XBPS (Void)
    if command -v xbps-install >/dev/null 2>&1; then
        PM_LIST+=("xbps")
        PM_PATH["xbps"]="$(command -v xbps-install)"
        if xbps-install --version >/dev/null 2>&1; then
            PM_STATUS["xbps"]="ok"
            echo -e "  ${GREEN}✓${NC} XBPS (Void Linux) - Available"
        else
            PM_STATUS["xbps"]="error"
            echo -e "  ${RED}✗${NC} XBPS - Issues detected"
        fi
    fi
    
    echo ""
    echo -e "${BOLD}🐋 Universal Package Sources...${NC}"
    
    # Snap
    if command -v snap >/dev/null 2>&1; then
        PM_LIST+=("snap")
        PM_PATH["snap"]="$(command -v snap)"
        if snap version >/dev/null 2>&1; then
            PM_STATUS["snap"]="ok"
            echo -e "  ${GREEN}✓${NC} Snap - Available"
        else
            PM_STATUS["snap"]="error"
            echo -e "  ${RED}✗${NC} Snap - Issues detected"
        fi
    else
        echo -e "  ${GRAY}○${NC} Snap - Not installed"
    fi
    
    # Flatpak
    if command -v flatpak >/dev/null 2>&1; then
        PM_LIST+=("flatpak")
        PM_PATH["flatpak"]="$(command -v flatpak)"
        if flatpak --version >/dev/null 2>&1; then
            PM_STATUS["flatpak"]="ok"
            echo -e "  ${GREEN}✓${NC} Flatpak - Available"
        else
            PM_STATUS["flatpak"]="error"
            echo -e "  ${RED}✗${NC} Flatpak - Issues detected"
        fi
    else
        echo -e "  ${GRAY}○${NC} Flatpak - Not installed"
    fi
    
    # AppImage (just check for tools)
    if command -v appimagetool >/dev/null 2>&1 || [ -d "$HOME/Applications" ]; then
        PM_LIST+=("appimage")
        echo -e "  ${GREEN}✓${NC} AppImage - Supported"
    else
        echo -e "  ${GRAY}○${NC} AppImage - Basic support"
    fi
    
    # Homebrew on Linux
    if command -v brew >/dev/null 2>&1; then
        PM_LIST+=("brew")
        PM_PATH["brew"]="$(command -v brew)"
        if brew --version >/dev/null 2>&1; then
            PM_STATUS["brew"]="ok"
            echo -e "  ${GREEN}✓${NC} Homebrew (Linux) - Available"
        else
            PM_STATUS["brew"]="error"
            echo -e "  ${RED}✗${NC} Homebrew - Issues detected"
        fi
    else
        echo -e "  ${GRAY}○${NC} Homebrew - Not installed"
    fi
    
    # Nix
    if command -v nix >/dev/null 2>&1; then
        PM_LIST+=("nix")
        echo -e "  ${GREEN}✓${NC} Nix - Available"
    else
        echo -e "  ${GRAY}○${NC} Nix - Not installed"
    fi
    
    echo ""
    
    # Export for use in other modules
    export DISTRO_NAME DISTRO_ID DISTRO_VERSION ARCH INIT
    export PM_LIST PM_STATUS PM_PATH
}
