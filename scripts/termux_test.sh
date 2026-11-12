
#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
#       TERMUX ENVIRONMENT TEST SCRIPT
#       Created by: Hunter zen RU
# ==========================================

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}"
echo "======================================"
echo "       TERMUX SYSTEM TEST"
echo "======================================"
echo -e "${RESET}"

# Test 1: Shell
echo -n "[1] Shell environment: "
if [ -n "$BASH_VERSION" ]; then
    echo -e "${GREEN}PASS${RESET} (Bash $BASH_VERSION)"
else
    echo -e "${RED}FAIL${RESET}"
fi

# Test 2: Termux environment
echo -n "[2] Termux environment: "
if [ -d "/data/data/com.termux/files/usr" ]; then
    echo -e "${GREEN}PASS${RESET}"
else
    echo -e "${RED}FAIL${RESET}"
fi

# Test 3: Storage
echo -n "[3] Storage access: "
if [ -d "$HOME" ] && [ -w "$HOME" ]; then
    echo -e "${GREEN}PASS${RESET}"
else
    echo -e "${RED}FAIL${RESET}"
fi

# Test 4: Internet
echo -n "[4] Internet connection: "
if command -v curl >/dev/null 2>&1; then
    if curl -Is --max-time 5 https://google.com >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${RESET}"
    else
        echo -e "${RED}FAIL${RESET}"
    fi
else
    echo -e "${YELLOW}SKIP${RESET} (curl not installed)"
fi

# Test 5: Package manager
echo -n "[5] Package manager: "
if command -v pkg >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${RESET}"
else
    echo -e "${RED}FAIL${RESET}"
fi

# Test 6: Basic commands
echo -n "[6] Basic commands: "
commands=("ls" "cat" "echo" "grep" "sed" "awk")

missing=0

for cmd in "${commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing=$((missing + 1))
    fi
done

if [ "$missing" -eq 0 ]; then
    echo -e "${GREEN}PASS${RESET}"
else
    echo -e "${YELLOW}WARNING${RESET} ($missing missing)"
fi

# Test 7: Architecture
echo -e "[7] Architecture: ${GREEN}$(uname -m)${RESET}"

# Test 8: Android version
echo -n "[8] Android version: "
if command -v getprop >/dev/null 2>&1; then
    getprop ro.build.version.release
else
    echo "Unknown"
fi

# Test 9: Temporary file
echo -n "[9] File creation: "
testfile="$HOME/.termux_test_file"
if echo "Termux test" > "$testfile" 2>/dev/null; then
    rm -f "$testfile"
    echo -e "${GREEN}PASS${RESET}"
else
    echo -e "${RED}FAIL${RESET}"
fi

# Test 10: Python
echo -n "[10] Python: "
if command -v python >/dev/null 2>&1; then
    python --version
else
    echo -e "${YELLOW}NOT INSTALLED${RESET}"
fi

# Summary
echo ""
echo "======================================"
echo "          SYSTEM INFORMATION"
echo "======================================"
echo "Device: $(getprop ro.product.model 2>/dev/null)"
echo "Android: $(getprop ro.build.version.release 2>/dev/null)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Shell: $SHELL"
echo "Home: $HOME"
echo "Prefix: $PREFIX"
echo ""
echo -e "${CYAN}Termux test completed!${RESET}"
echo "======================================"
