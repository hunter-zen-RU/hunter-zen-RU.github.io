#!/usr/bin/env bash
# Navigation utilities for packser

# Arrow key navigation using fzf or manual
navigate_menu() {
    local title="$1"
    shift
    local options=("$@")
    
    if command -v fzf >/dev/null 2>&1; then
        local selected=$(printf "%s\n" "${options[@]}" | fzf --height=40% --reverse --border --prompt="$title > " --header="Use arrow keys to navigate, Enter to select")
        echo "$selected"
    elif command -v gum >/dev/null 2>&1; then
        gum choose --cursor="▶ " --header="$title" "${options[@]}"
    else
        # Manual navigation
        local i=1
        echo -e "${BOLD}$title${NC}" >&2
        echo >&2
        for opt in "${options[@]}"; do
            echo -e "  ${GREEN}$i)${NC} $opt" >&2
            ((i++))
        done
        echo >&2
        read -p "$(echo -e ${BOLD}Choose [1-$((i-1))]:${NC} )" choice >&2
        echo "${options[$((choice-1))]}"
    fi
}

# Multi-select with fzf
multi_select() {
    local title="$1"
    shift
    local options=("$@")
    
    if command -v fzf >/dev/null 2>&1; then
        printf "%s\n" "${options[@]}" | fzf -m --height=60% --reverse --border --prompt="$title (TAB to select) > "
    elif command -v gum >/dev/null 2>&1; then
        gum choose --no-limit --cursor="▶ " --selected="✓ " --header="$title" "${options[@]}"
    else
        echo -e "${BOLD}$title${NC}" >&2
        echo -e "${YELLOW}Enter numbers separated by spaces${NC}" >&2
        local i=1
        for opt in "${options[@]}"; do
            echo -e "  ${GREEN}$i)${NC} $opt" >&2
            ((i++))
        done
        echo >&2
        read -p "Choices: " choices >&2
        for c in $choices; do
            echo "${options[$((c-1))]}"
        done
    fi
}

# Checkbox style menu
checkbox_menu() {
    local title="$1"
    local height="$2"
    local width="$3"
    shift 3
    local items=("$@")
    
    if command -v dialog >/dev/null 2>&1; then
        dialog --checklist "$title" "$height" "$width" "${#items[@]}" "${items[@]}" 3>&1 1>&2 2>&3
    elif command -v whiptail >/dev/null 2>&1; then
        whiptail --title "$title" --checklist "$title" "$height" "$width" "${#items[@]}" "${items[@]}" 3>&1 1>&2 2>&3
    fi
}
