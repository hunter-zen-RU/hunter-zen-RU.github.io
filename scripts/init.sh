#!/bin/bash

# Configuration
BASE_URL="https://hunter-zen-ru.github.io/scripts"

# Colors for terminal UI
BLUE='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}=======================================${NC}"
echo -e "${GREEN} Fetching available scripts...        ${NC}"
echo -e "${BLUE}=======================================${NC}"

# Fetch the page HTML source dynamically
RAW_HTML=$(curl -sL "$BASE_URL/")
if [ -z "$RAW_HTML" ]; then
    echo -e "${RED}Error: Unable to reach $BASE_URL${NC}"
    exit 1
fi

# Extract unique script filenames from HTML layout
options=$(echo "$RAW_HTML" | grep -oE 'href="[^"]+\.(sh|py|pl|txt|bash)"' | sed -E 's/href="([^"]+)"/\1/' | sed 's|.*/||' | sort -u)

if [ -z "$options" ]; then
    echo -e "${YELLOW}No scripts explicitly discovered in index. Using local fallback list...${NC}"
    SCRIPTS=("example_script.sh" "setup.sh" "test.sh")
else
    IFS=$'\n' read -rd '' -a SCRIPTS <<< "$options"
fi

# Interactive Menu Loop
while true; do
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${CYAN}    HUNTER-ZEN-RU REMOTE SCRIPTS MANAGER         ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Available Remote Scripts:${NC}"
    
    for i in "${!SCRIPTS[@]}"; do
        printf "  ${GREEN}%2d)${NC} %s\n" $((i+1)) "${SCRIPTS[$i]}"
    done
    
    echo -e "  ${RED} q)${NC} Exit Manager"
    echo -e "${BLUE}=================================================${NC}"
    echo -n "Select a script number to execute/view: "
    
    # CRITICAL: Read interactive choices directly from the TTY context
    read -r choice < /dev/tty

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo -e "${GREEN}Goodbye!${NC}"
        break
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt "${#SCRIPTS[@]}" ]; then
        echo -e "${RED}Invalid selection. Press enter to try again.${NC}"
        read -r < /dev/tty
        continue
    fi

    SELECTED_SCRIPT="${SCRIPTS[$((choice-1))]}"
    SCRIPT_URL="$BASE_URL/$SELECTED_SCRIPT"

    # Action Sub-Menu
    while true; do
        clear
        echo -e "${BLUE}Selected:${NC} ${YELLOW}$SELECTED_SCRIPT${NC}"
        echo -e "${BLUE}Source:  ${NC} $SCRIPT_URL"
        echo "-------------------------------------------------"
        echo -e " ${GREEN}1)${NC} Preview script code"
        echo -e " ${GREEN}2)${NC} Run script directly (via bash pipe)"
        echo -e " ${GREEN}3)${NC} Download and save script locally"
        echo -e " ${GREEN}4)${NC} Back to Main Menu"
        echo "-------------------------------------------------"
        echo -n "Choose action: "
        read -r action < /dev/tty

        case "$action" in
            1)
                echo -e "\n${CYAN}--- Script Preview ---${NC}"
                # Swapped out interactive 'less' to preserve TTY control flow
                curl -sL "$SCRIPT_URL" | head -n 40
                echo -e "\n${YELLOW}[Preview ends here (First 40 lines shown)]${NC}"
                echo "Press enter to return..."
                read -r < /dev/tty
                ;;
            2)
                echo -e "\n${GREEN}--- Executing $SELECTED_SCRIPT ---${NC}"
                # Run the targeted payload dynamically
                curl -sL "$SCRIPT_URL" | bash
                echo -e "\n${YELLOW}Execution complete. Press enter to return.${NC}"
                read -r < /dev/tty
                break
                ;;
            3)
                echo -n "Enter target directory (Default: current directory): "
                read -r save_path < /dev/tty
                save_path="${save_path:-.}"
                mkdir -p "$save_path"
                curl -sL "$SCRIPT_URL" -o "$save_path/$SELECTED_SCRIPT"
                echo -e "${GREEN}Saved safely to: $save_path/$SELECTED_SCRIPT${NC}"
                echo -e "Press enter to return..."
                read -r < /dev/tty
                break
                ;;
            4)
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Press enter to retry.${NC}"
                read -r < /dev/tty
                ;;
        esac
    done
done
