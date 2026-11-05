#!/bin/bash
# ==============================================================================
# PROJECT: REPODIR (Repository Auditor)
# DESCRIPTION: Cross-platform workspace manager, custom interactive shell, 
#              and autonomous OpenCode AI agent pipeline orchestrator.
# ==============================================================================
set -e

# Configuration Defaults
CONFIG_DIR="$HOME/.repodir"
CONFIG_FILE="$CONFIG_DIR/conf"
mkdir -p "$CONFIG_DIR"

# Global tracking variables
TARGET_REPO=""
GPH_KEY=""
YML_MODE=false

# Load existing configurations if present
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; exit 1; }

save_config() {
    cat <<EOF > "$CONFIG_FILE"
TARGET_REPO="$TARGET_REPO"
GPH_KEY="$GPH_KEY"
EOF
}

prompt_for_key() {
    if [ -z "$GPH_KEY" ]; then
        log_warn "Authentication token missing."
        echo "Opening browser to fetch GitHub Auth keys..."
        # Cross-platform browser link execution
        if command -v xdg-open &>/dev/null; then xdg-open "https://github.com";
        elif command -v open &>/dev/null; then open "https://github.com";
        else echo "Please navigate to: https://github.com"; fi
        
        echo -n "🔑 Enter your GitHub Personal Key (or press enter to skip): "
        read -r GPH_KEY
        save_config
    fi
}

install_system() {
    log_info "Installing REPODIR locally to system workspace..."
    cp "$0" "$CONFIG_DIR/repodir" 2>/dev/null || cat "$0" > "$CONFIG_DIR/repodir"
    chmod +x "$CONFIG_DIR/repodir"

    # Persistent shell alias generation
    SHELL_RC=""
    if [[ "$SHELL" == */zsh ]]; then SHELL_RC="$HOME/.zshrc";
    elif [[ "$SHELL" == */bash ]]; then SHELL_RC="$HOME/.bashrc"; fi

    if [ -n "$SHELL_RC" ] && [ -f "$SHELL_RC" ]; then
        if ! grep -q "alias repodir=" "$SHELL_RC"; then
            echo "alias repodir='$CONFIG_DIR/repodir'" >> "$SHELL_RC"
            log_success "Alias configured dynamically in $SHELL_RC. Run 'source $SHELL_RC' or restart shell."
        fi
    fi
}

# ==============================================================================
# PIPELINE ATOMIC ACTIONS (No-Shell CLI Args)
# ==============================================================================
action_unzip_to_root() {
    local target_pattern="${1:-*.zip}"
    local keep_zip="${2:-false}"
    
    local target_zip
    target_zip=$(find . -maxdepth 2 -name "$target_pattern" | head -n 1)
    
    if [ -z "$target_zip" ] || [ ! -f "$target_zip" ]; then
        log_error "No valid zip file detected matching query context: $target_pattern"
    fi

    log_info "Unzipping archive target ($target_zip) directly to root context..."
    unzip -o -q "$target_zip" -d temp_unzip
    shopt -s dotglob
    mv -v temp_unzip/* ./ || true
    rmdir temp_unzip || rm -rf temp_unzip

    if [ "$keep_zip" = "false" ]; then
        rm -f "$target_zip"
        log_info "Cleaned up source archive tracker."
    fi
    log_success "Unzip operation complete."
}

action_install_opencode() {
    log_info "Initializing OpenCode AI Engine deployment..."
    if command -v opencode &>/dev/null; then
        log_success "OpenCode binary is already live in this shell PATH."
    else
        curl -fsSL https://opencode.ai/v2/install | bash
        log_success "OpenCode AI platform successfully registered."
    fi
}

# ==============================================================================
# THE CUSTOM WORKSPACE INTERACTIVE SHELL
# ==============================================================================
launch_custom_shell() {
    clear
    echo "=================================================================="
    echo " REPODIR CUSTOM ENVIRONMENT SHELL (Auditor Terminal Mode) "
    echo " Working Directory: $(pwd)"
    echo " Type 'help' to review commands, or 'exit' to escape."
    echo "=================================================================="
    
    while true; do
        echo -n "🔮 repodir:$(basename "$(pwd)") $ "
        read -r cmd_input args
        
        case "$cmd_input" in
            help)
                echo "  unzip-root [pattern] [--keep] - Extract zip files inline"
                echo "  opencode                    - Spin up OpenCode AI Session"
                echo "  git-status                  - Inspect file audit status"
                echo "  edit [file]                 - Quickly edit project file text"
                echo "  exit                        - Close the auditor workspace terminal"
                ;;
            unzip-root)
                local keep="false"
                [[ "$args" == *"--keep"* ]] && keep="true"
                local clean_args
                clean_args=$(echo "$args" | sed 's/--keep//g' | xargs)
                action_unzip_to_root "${clean_args:-*.zip}" "$keep"
                ;;
            opencode)
                action_install_opencode
                if command -v opencode &>/dev/null; then
                    opencode
                fi
                ;;
            git-status)
                git status || echo "Not a git repository tracker workspace."
                ;;
            edit)
                if [ -z "$args" ]; then echo "Specify a target filename."; else ${EDITOR:-nano} "$args"; fi
                ;;
            exit)
                echo "Exiting REPODIR auditor shell layer."
                break
                ;;
            "") ;;
            *)
                # Fallback to traditional local system shell pass-through
                eval "$cmd_input $args"
                ;;
        esac
    done
}

# ==============================================================================
# MENU-DRIVEN INTERACTIVE INTERFACE
# ==============================================================================
launch_menu_interface() {
    while true; do
        clear
        echo "===================================================="
        echo " REPODIR MAIN MENU INTERFACE "
        echo " Repository: ${TARGET_REPO:-Not Selected}"
        echo "===================================================="
        echo "1) Select / Change Target Git Repository"
        echo "2) Authorize / Update GitHub Key Config"
        echo "3) Launch OpenCode AI Session Agent"
        echo "4) Unzip Archive to Root Folder"
        echo "5) Access Custom Interactive Shell"
        echo "6) Persist/Install App to System PATH Alias"
        echo "7) Exit Management Matrix"
        echo "===================================================="
        echo -n "Choose an operation [1-7]: "
        read -r menu_choice

        case $menu_choice in
            1)
                echo -n "Enter target git repo URL: "
                read -r TARGET_REPO
                save_config
                ;;
            2)
                GPH_KEY=""
                prompt_for_key
                ;;
            3)
                action_install_opencode
                if command -v opencode &>/dev/null; then opencode; fi
                ;;
            4)
                echo -n "Enter archive pattern search match (default: *.zip): "
                read -r pat
                action_unzip_to_root "${pat:-*.zip}" "false"
                echo "Press enter to return..."; read -r _
                ;;
            5)
                launch_custom_shell
                ;;
            6)
                install_system
                echo "Press enter to return..."; read -r _
                ;;
            7)
                exit 0
                ;;
        esac
    done
}

# ==============================================================================
# INITIALIZATION RUNTIME CONTROL (Argument Parsers)
# ==============================================================================
# Parse upfront flags that break sequential orders
for arg in "$@"; do
    if [ "$arg" == "--yml" ]; then
        YML_MODE=true
    fi
done

# Argument Router Matrix
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            TARGET_REPO="$2"
            shift 2
            ;;
        -k)
            GPH_KEY="$2"
            shift 2
            ;;
        --unzip-to-root)
            # Find next parameters dynamically
            pattern_arg=""
            keep_arg="false"
            if [[ -n "$2" && "$2" != --* ]]; then
                pattern_arg="$2"
                shift
            fi
            if [[ "$2" == "--keep" || "$3" == "--keep" ]]; then
                keep_arg="true"
                shift
            fi
            action_unzip_to_root "${pattern_arg:-*.zip}" "$keep_arg"
            exit 0
            ;;
        --yml)
            shift
            ;;
        *)
            log_error "Unknown argument runtime routing rule parsed: $1"
            ;;
    esac
done

# Execute Environment Strategy Check
if [ "$YML_MODE" = true ]; then
    log_info "CI/CD execution layer identified (--yml). Suppressing interactive menus."
    # Headless workflow processing logic goes here...
    if [ -n "$TARGET_REPO" ]; then
        log_info "Automated Pipeline tracking active repo: $TARGET_REPO"
    fi
    exit 0
fi

# Detect system execution format
if [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "darwin"* ]]; then
    install_system
fi

# Evaluate targeted startup execution workflows
if [ -n "$TARGET_REPO" ]; then
    log_info "Targeted startup initiated for: $TARGET_REPO"
    if [ -z "$GPH_KEY" ]; then
        prompt_for_key
    fi
launch_custom_shell
else
# Fallback to menu driven execution workspace
launch_menu_interface
fi
