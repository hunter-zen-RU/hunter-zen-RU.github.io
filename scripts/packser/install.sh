#!/usr/bin/env bash
# packser installer / live runner
#
# Hosted at:
#   https://hunter-zen-ru.github.io/scripts/packser/install.sh
#
# Usage:
#   curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash
#   curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash -s -- --install
#   curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash -s -- --live
#
# Options:
#   -i, --install   Install system-wide to /usr/local, then run
#   -l, --live      Download a temporary copy, run once, then delete it
#   -h, --help      Show this help
#
# Environment overrides:
#   PACKSER_BASE_URL      Where packser files are hosted
#   PACKSER_INSTALL_DIR   System-wide data directory (default: /usr/local/share/packser)
#   PACKSER_BIN_DIR       Directory for the packser command (default: /usr/local/bin)

if [ -z "${BASH_VERSION:-}" ]; then
    echo "packser installer requires bash. Run it with: bash install.sh" >&2
    exit 1
fi

set -euo pipefail

VERSION="1.1"
BASE_URL="${PACKSER_BASE_URL:-https://hunter-zen-ru.github.io/scripts/packser}"
BASE_URL="${BASE_URL%/}"

INSTALL_DIR="${PACKSER_INSTALL_DIR:-/usr/local/share/packser}"
BIN_DIR="${PACKSER_BIN_DIR:-/usr/local/bin}"
BIN_LINK="${BIN_DIR}/packser"

# Files required to run packser. Keep this list in sync with the project.
FILES=(
    "packser"
    "README.md"
    "lib/utils.sh"
    "lib/detect.sh"
    "lib/pm.sh"
    "lib/database.sh"
    "lib/navigation.sh"
    "lib/search.sh"
    "lib/marking.sh"
    "lib/ui.sh"
)

if [ -t 1 ]; then
    BOLD=$'\033[1m'
    CYAN=$'\033[0;36m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    NC=$'\033[0m'
else
    BOLD=''
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
fi

TMP_DIR=''
MODE=''

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR"
    fi
}

remove_tmp() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR"
    fi
    TMP_DIR=''
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say() {
    printf '%s\n' "$*"
}

ok() {
    printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"
}

die() {
    printf '%sError:%s %s\n' "$RED" "$NC" "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
packser installer v${VERSION}

Usage:
  install.sh [--install | --live]

Options:
  -i, --install   Install system-wide to ${INSTALL_DIR},
                  link ${BIN_LINK}, then run packser.
  -l, --live      Download a temporary copy, run it once, then delete it.
  -h, --help      Show this help.

Without an option, you will be prompted to choose install or live use.

Environment:
  PACKSER_BASE_URL      File host (default: ${BASE_URL})
  PACKSER_INSTALL_DIR   Install directory (default: ${INSTALL_DIR})
  PACKSER_BIN_DIR       Command directory (default: ${BIN_DIR})

Examples:
  curl -fsSL ${BASE_URL}/install.sh | bash
  curl -fsSL ${BASE_URL}/install.sh | bash -s -- --install
  curl -fsSL ${BASE_URL}/install.sh | bash -s -- --live
EOF
}

has_tty() {
    # /dev/tty can exist without being usable (for example in CI or when piped).
    (exec </dev/tty) >/dev/null 2>&1
}

read_from_tty() {
    local __var="$1"
    local __value=''

    if ! has_tty; then
        die "No terminal available. Re-run with --install or --live."
    fi

    if ! IFS= read -r __value < /dev/tty; then
        die "Could not read from the terminal."
    fi

    printf -v "$__var" '%s' "$__value"
}

prompt_mode() {
    local choice=''

    say ""
    say "${BOLD}How do you want to use packser?${NC}"
    say ""
    say "  ${BOLD}1) Install${NC}"
    say "     Install system-wide in ${INSTALL_DIR},"
    say "     add the ${BIN_LINK} command, then run it."
    say "     Requires sudo. Files stay installed."
    say ""
    say "  ${BOLD}2) Live use${NC}"
    say "     Download a temporary copy, run it once,"
    say "     then delete the downloaded files automatically."
    say "     Nothing is installed."
    say ""

    while :; do
        printf '  Choose [1/2]: '
        read_from_tty choice

        case "$choice" in
            1|i|I|install|Install)
                MODE='install'
                break
                ;;
            2|l|L|live|Live)
                MODE='live'
                break
                ;;
            q|Q|quit|Quit)
                say "Cancelled."
                exit 0
                ;;
            *)
                warn "Please enter 1 for install or 2 for live use."
                ;;
        esac
    done
}

download_file() {
    local relative_path="$1"
    local destination="$2"
    local url="${BASE_URL}/${relative_path}"
    local partial="${destination}.part"

    mkdir -p "$(dirname "$destination")"
    rm -f -- "$partial"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 15 \
            "$url" -o "$partial"; then
            rm -f -- "$partial"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --tries=3 --timeout=15 -O "$partial" "$url"; then
            rm -f -- "$partial"
            return 1
        fi
    else
        die "curl or wget is required to download packser."
    fi

    if [ ! -s "$partial" ]; then
        rm -f -- "$partial"
        return 1
    fi

    mv -f -- "$partial" "$destination"
}

download_all() {
    local destination="$1"
    local file

    say ""
    say "${CYAN}Downloading packser v${VERSION}...${NC}"
    say "  Source: ${BASE_URL}"

    for file in "${FILES[@]}"; do
        if ! download_file "$file" "${destination}/${file}"; then
            die "Failed to download ${BASE_URL}/${file}"
        fi
        printf '  %s✓%s %s\n' "$GREEN" "$NC" "$file"
    done

    chmod +x "${destination}/packser"

    # Fail early on a corrupted or incomplete download.
    if ! bash -n "${destination}/packser" >/dev/null 2>&1; then
        die "Downloaded packser executable is not valid shell code."
    fi

    for file in "${destination}"/lib/*.sh; do
        if ! bash -n "$file" >/dev/null 2>&1; then
            die "Downloaded module is not valid shell code: $(basename "$file")"
        fi
    done

    say ""
}

as_root() {
    if [ "${EUID}" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

prepare_sudo() {
    if [ "${EUID}" -eq 0 ]; then
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "sudo is required to install system-wide. Run as root or use --live."
    fi

    say "  System-wide installs require sudo privileges."
    if ! sudo -v; then
        die "sudo authentication failed."
    fi
}

install_packser() {
    local source_dir="$1"

    case "$INSTALL_DIR" in
        ""|"/"|".")
            die "Refusing to install into an unsafe directory: '${INSTALL_DIR}'"
            ;;
    esac

    say "${CYAN}Installing packser system-wide...${NC}"
    prepare_sudo

    as_root mkdir -p -- "$BIN_DIR"
    as_root rm -rf -- "$INSTALL_DIR"
    as_root mkdir -p -- "$INSTALL_DIR"

    # Copy as root so the installed files are not owned by the calling user.
    as_root cp -R -- "${source_dir}/." "$INSTALL_DIR/"
    as_root chmod 755 -- "${INSTALL_DIR}/packser"
    as_root ln -sfn -- "${INSTALL_DIR}/packser" "$BIN_LINK"

    say ""
    ok "Installed to ${INSTALL_DIR}"
    ok "Command available at ${BIN_LINK}"

    case ":${PATH}:" in
        *":${BIN_DIR}:"*) ;;
        *)
            warn "${BIN_DIR} is not in your PATH."
            say "     Add it with: export PATH=\"${BIN_DIR}:\$PATH\""
            ;;
    esac

    say ""
}

run_packser() {
    local executable="$1"
    local status=0

    # When this installer is piped from curl, stdin is the script itself.
    # Give packser the controlling terminal so its menus work.
    if has_tty; then
        "$executable" < /dev/tty || status=$?
    else
        "$executable" || status=$?
    fi

    return "$status"
}

run_install_mode() {
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/packser-install.XXXXXX")
    download_all "$TMP_DIR"
    install_packser "$TMP_DIR"

    remove_tmp

    say "${CYAN}Starting packser...${NC}"
    say ""
    run_packser "$BIN_LINK"
}

run_live_mode() {
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/packser-live.XXXXXX")
    download_all "$TMP_DIR"

    say "${CYAN}Starting live copy...${NC}"
    say "  Temporary files: ${TMP_DIR}"
    say "  They will be deleted when packser exits."
    say ""

    local status=0
    run_packser "${TMP_DIR}/packser" || status=$?

    remove_tmp

    say ""
    ok "Temporary live copy deleted."
    return "$status"
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -i|--install)
                MODE='install'
                ;;
            -l|--live)
                MODE='live'
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
        shift
    done

    say ""
    say "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    say "${CYAN}${BOLD}║                 PACKSER INSTALLER v${VERSION}                  ║${NC}"
    say "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    if [ -z "$MODE" ]; then
        prompt_mode
    fi

    case "$MODE" in
        install)
            run_install_mode
            ;;
        live)
            run_live_mode
            ;;
        *)
            die "Invalid mode: ${MODE}"
            ;;
    esac
}

main "$@"
