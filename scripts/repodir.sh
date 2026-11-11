#!/usr/bin/env bash
# ==============================================================================
# PROJECT     : REPODIR v3 (Repository Auditor, Builder & AI Maintainer)
# DEVELOPER   : Hunter Zen RU
# DESCRIPTION : Cross-platform workspace manager, security auditor, project
#               builder (APK / Windows / Linux binaries ...), custom interactive
#               shell and OpenCode AI pipeline orchestrator.
#
# RUN         : curl -fsSL https://hunter-zen-ru.github.io/scripts/repodir.sh | bash
# WITH ARGS   : curl -fsSL https://hunter-zen-ru.github.io/scripts/repodir.sh | bash -s -- --help
# ==============================================================================
# NOTE: no `set -e` / `set -u` on purpose. This is an interactive tool: one failed
# command must never kill the whole session. (pipefail is on, so avoid `| grep -q`
# in conditions - use here-strings instead.)
set -o pipefail

VERSION="3.0.0"
SELF_URL="https://hunter-zen-ru.github.io/scripts/repodir.sh"
CHECKSUM_URL="${SELF_URL}.sha256"
OPENCODE_INSTALL_URL="https://opencode.ai/install"

ROOT_DIR="${REPODIR_HOME:-$HOME/.repodir}"
PROFILE="${REPODIR_PROFILE:-default}"
BIN_DIR="$HOME/.local/bin"
RC_START="# >>> repodir >>>"
RC_END="# <<< repodir <<<"

# Persisted settings (profile-scoped)
CONFIG_KEYS="TARGET_REPO GPH_KEY AI_MODEL SLACK_WEBHOOK DISCORD_WEBHOOK TG_TOKEN TG_CHAT"
TARGET_REPO=""; GPH_KEY=""; AI_MODEL=""
SLACK_WEBHOOK=""; DISCORD_WEBHOOK=""; TG_TOKEN=""; TG_CHAT=""

# Runtime flags
YML_MODE=false; KEEP_ZIP=false; ASSUME_YES=false; AUDIT_FULL=false; NOTIFY=false
SAVE_BASELINE=false; SHALLOW=false; CLONE_BRANCH=""; EXPORT_FMTS=""
TARGET_FROM_CLI=false; SECRET_HITS=0; LAST_REPORT=""
ACTIONS=()
OS_NAME="linux"; ARCH="$(uname -m 2>/dev/null)"

# Files/dirs that are never audited
PRUNE=( -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' \
        -not -path '*/venv/*' -not -path '*/vendor/*' -not -path '*/target/*' \
        -not -path '*/dist/*' -not -path '*/build/*' )

# ==============================================================================
# TERMINAL / LOGGING
# ==============================================================================
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[0;33m'
    C_BLU=$'\033[0;34m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_RST=""
fi

log_info()    { printf '%s[INFO]%s %s\n'    "$C_BLU" "$C_RST" "$*"; }
log_success() { printf '%s[SUCCESS]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n'    "$C_YLW" "$C_RST" "$*" >&2; }
log_error()   { printf '%s[ERROR]%s %s\n'   "$C_RED" "$C_RST" "$*" >&2; }   # never exits
die()         { log_error "$*"; exit 1; }                                    # fatal only

# Input: under `curl | bash` stdin is the script, so every read uses /dev/tty.
TTY_IN=""
if [ -t 0 ]; then
    TTY_IN="/dev/stdin"
elif ( : </dev/tty ) 2>/dev/null; then
    TTY_IN="/dev/tty"
fi
INTERACTIVE=false
[ -n "$TTY_IN" ] && INTERACTIVE=true

# ask VAR "prompt" [silent]
ask() {
    local __var="$1" __prompt="$2" __mode="${3:-}" __reply=""
    if [ "$INTERACTIVE" != true ]; then printf -v "$__var" '%s' ""; return 1; fi
    if [ "$__mode" = "silent" ]; then
        IFS= read -rs -p "$__prompt" __reply <"$TTY_IN" || return 1
        echo >&2
    else
        IFS= read -e -r -p "$__prompt" __reply <"$TTY_IN" || return 1
    fi
    printf -v "$__var" '%s' "$__reply"
}

# confirm "question" [default y|n]
confirm() {
    local a def="${2:-n}" hint="[y/N]"
    [ "$def" = "y" ] && hint="[Y/n]"
    ask a "$1 $hint: " || return 1
    a="${a:-$def}"
    case "$a" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# confirm_or_yes: honours --yes (needed for headless / CI runs)
confirm_or_yes() {
    [ "$ASSUME_YES" = true ] && return 0
    if [ "$INTERACTIVE" != true ]; then
        log_error "Confirmation required but no terminal. Re-run with --yes to approve: $1"
        return 1
    fi
    confirm "$1" "${2:-y}"
}

pause() { local d; ask d "Press enter to continue..." || true; }
clear_screen() { [ -t 1 ] && clear; return 0; }

detect_os() {
    case "${OSTYPE:-}" in
        darwin*)              OS_NAME="macos" ;;
        msys*|cygwin*|win32*) OS_NAME="windows" ;;
        *)
            if [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]; then OS_NAME="termux"
            elif grep -qi microsoft /proc/version 2>/dev/null; then OS_NAME="wsl"
            else OS_NAME="linux"; fi ;;
    esac
}

open_url() {
    case "$OS_NAME" in
        windows) cmd.exe //c start "" "$1" >/dev/null 2>&1 & ;;
        wsl)     if command -v wslview >/dev/null 2>&1; then wslview "$1" >/dev/null 2>&1 &
                 else cmd.exe /c start "" "$1" >/dev/null 2>&1 & fi ;;
        macos)   open "$1" >/dev/null 2>&1 & ;;
        termux)  termux-open-url "$1" >/dev/null 2>&1 & ;;
        *)       if command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 &
                 else echo "Please navigate to: $1"; fi ;;
    esac
    return 0
}

need() {  # need cmd [cmd...]
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || { log_error "Required tool not found: $c"; return 1; }
    done
}

# ==============================================================================
# PROFILES / DIRECTORIES / CONFIG
# ==============================================================================
setup_dirs() {
    case "$PROFILE" in *[!A-Za-z0-9_-]*|"") die "Invalid profile name: '$PROFILE' (use letters, digits, - _)" ;; esac
    if [ "$PROFILE" = "default" ]; then DATA_DIR="$ROOT_DIR"; else DATA_DIR="$ROOT_DIR/profiles/$PROFILE"; fi
    CONFIG_FILE="$DATA_DIR/conf"
    REPORT_DIR="$DATA_DIR/reports"
    HIST_FILE="$DATA_DIR/history"
    REPOS_FILE="$DATA_DIR/repos.list"
    BASE_DIR="$DATA_DIR/baselines"
    BUILD_LOG_DIR="$DATA_DIR/builds"
    PLUGIN_DIR="$ROOT_DIR/plugins"
    WORKSPACE="${REPODIR_WORKSPACE:-$HOME/repodir-workspace}"
    [ "$PROFILE" != "default" ] && WORKSPACE="$WORKSPACE/$PROFILE"
    mkdir -p "$DATA_DIR" 2>/dev/null && chmod 700 "$ROOT_DIR" "$DATA_DIR" 2>/dev/null
    return 0
}

load_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    local k v
    while IFS='=' read -r k v; do
        v="${v%\"}"; v="${v#\"}"
        case " $CONFIG_KEYS " in *" $k "*) printf -v "$k" '%s' "$v" ;; esac
    done < "$CONFIG_FILE"
}

save_config() {
    mkdir -p "$DATA_DIR" || return 1
    local k
    ( umask 077
      : > "$CONFIG_FILE"
      for k in $CONFIG_KEYS; do printf '%s=%s\n' "$k" "${!k}" >> "$CONFIG_FILE"; done )
    chmod 600 "$CONFIG_FILE" 2>/dev/null
    return 0
}

action_config() {  # config KEY=VALUE | config (show)
    local kv="${1:-}" k v
    if [ -z "$kv" ]; then
        echo "Profile: $PROFILE   ($CONFIG_FILE)"
        for k in $CONFIG_KEYS; do
            v="${!k}"
            case "$k" in GPH_KEY|SLACK_WEBHOOK|DISCORD_WEBHOOK|TG_TOKEN) [ -n "$v" ] && v="(set, hidden)" ;; esac
            printf '  %-16s %s\n' "$k" "${v:-<empty>}"
        done
        return 0
    fi
    k="${kv%%=*}"; v="${kv#*=}"
    case " $CONFIG_KEYS " in *" $k "*) ;; *) log_error "Unknown key '$k'. Valid: $CONFIG_KEYS"; return 1 ;; esac
    printf -v "$k" '%s' "$v"; save_config && log_success "Saved $k"
}

action_profiles() {
    echo "Active profile: $PROFILE"
    echo "  default"
    [ -d "$ROOT_DIR/profiles" ] && ls -1 "$ROOT_DIR/profiles" 2>/dev/null | sed 's/^/  /'
    echo "Use: repodir --profile <name> ...   (profiles keep separate token, repos, reports, workspace)"
}

prompt_for_key() {
    if [ -n "$GPH_KEY" ]; then return 0; fi
    log_warn "GitHub token missing (needed for private repos / higher API limits)."
    if confirm "Open the GitHub token page in your browser?" y; then
        open_url "https://github.com/settings/personal-access-tokens/new"
    fi
    ask GPH_KEY "🔑 Enter your GitHub Personal Key (input hidden, enter to skip): " silent || true
    if [ -n "$GPH_KEY" ]; then save_config; log_success "Token saved to $CONFIG_FILE (chmod 600)."; fi
    return 0
}

# ==============================================================================
# SMALL UTILITIES
# ==============================================================================
json_esc() { printf '%s' "$1" | tr '\n\t\r' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
html_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
cap()      { [ "$1" -gt "$2" ] && echo "$2" || echo "$1"; }
count_lines() { [ -n "$1" ] && printf '%s\n' "$1" | wc -l | tr -d ' ' || echo 0; }

sha256_of() {
    if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl   >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
    else return 1; fi
}

ver_gt() {  # ver_gt A B -> success when A > B
    local IFS=. i x y
    local a=($1) b=($2)
    for i in 0 1 2; do
        x="${a[$i]:-0}"; y="${b[$i]:-0}"
        [ "$x" -gt "$y" ] 2>/dev/null && return 0
        [ "$x" -lt "$y" ] 2>/dev/null && return 1
    done
    return 1
}

# pick_from "prompt" < items  -> prints the chosen line (fzf if installed)
pick_from() {
    local prompt="$1" items=() line i=1 sel
    while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done
    [ ${#items[@]} -gt 0 ] || return 1
    if [ "$INTERACTIVE" != true ] || [ ${#items[@]} -eq 1 ]; then printf '%s' "${items[0]}"; return 0; fi
    if command -v fzf >/dev/null 2>&1; then
        printf '%s\n' "${items[@]}" | fzf --height 40% --reverse --prompt "$prompt > "
        return $?
    fi
    for line in "${items[@]}"; do printf '  %2d) %s\n' "$i" "$line" >&2; i=$((i+1)); done
    ask sel "$prompt [1-${#items[@]}]: " || return 1
    case "$sel" in ''|*[!0-9]*) return 1 ;; esac
    [ "$sel" -ge 1 ] && [ "$sel" -le "${#items[@]}" ] || return 1
    printf '%s' "${items[$((sel-1))]}"
}

# ask_text VAR "prompt" : like ask, but keeps a pre-filled value when given
ensure_arg() { # ensure_arg VAR "value" "prompt"
    if [ -n "$2" ]; then printf -v "$1" '%s' "$2"; return 0; fi
    ask "$1" "$3" || return 1
    [ -n "${!1}" ]
}

# ==============================================================================
# GIT  (token passed via env config header: never in the URL, .git/config or ps)
# ==============================================================================
normalize_repo() {
    case "$1" in
        http://*|https://*|git@*|ssh://*|file://*|/*|./*|../*|~*) printf '%s' "$1" ;;
        */*) printf 'https://github.com/%s.git' "${1%.git}" ;;
        *)   printf '%s' "$1" ;;
    esac
}

repo_name() {
    local n="${1%/}"
    n="${n##*/}"; n="${n##*:}"
    printf '%s' "${n%.git}"
}

repo_slug() {  # owner/repo for GitHub URLs / shorthand, empty otherwise
    local u="${1:-$TARGET_REPO}"
    case "$u" in
        *github.com[:/]*) u="${u#*github.com[:/]}"; u="${u%.git}"; u="${u%/}"
                          printf '%s' "$u" | cut -d/ -f1,2 ;;
        http*|git@*|ssh://*|/*|./*|../*|~*|"") ;;
        */*) printf '%s' "${u%.git}" ;;
    esac
}

git_auth() {
    if [ -n "$GPH_KEY" ]; then
        local b64
        b64=$(printf 'x-access-token:%s' "$GPH_KEY" | base64 | tr -d '\n')
        GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
        GIT_CONFIG_VALUE_0="Authorization: Basic $b64" \
        GIT_TERMINAL_PROMPT=0 git "$@"
    else
        GIT_TERMINAL_PROMPT=0 git "$@"
    fi
}

in_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

action_clone() {
    need git || return 1
    local url dest extra=()
    url=$(normalize_repo "${1:-$TARGET_REPO}")
    [ -n "$url" ] || { log_error "No repository set. Use -t owner/repo."; return 1; }
    dest="${2:-$WORKSPACE/$(repo_name "$url")}"
    [ "$SHALLOW" = true ] && extra+=(--depth 1)
    [ -n "$CLONE_BRANCH" ] && extra+=(--branch "$CLONE_BRANCH")

    if [ -d "$dest/.git" ]; then
        log_info "Repository exists, pulling latest: $dest"
        git_auth -C "$dest" pull --ff-only || log_warn "Pull failed (local changes or diverged history)."
    else
        mkdir -p "$(dirname "$dest")" || return 1
        log_info "Cloning $url -> $dest"
        git_auth clone ${extra[@]+"${extra[@]}"} "$url" "$dest" || { log_error "Clone failed. Check URL / token."; return 1; }
    fi
    cd "$dest" || return 1
    log_success "Working directory: $(pwd)"
}

# from <local-dir | .zip | owner/repo | url>  -> cd into that project
action_from() {
    local src="${1:-}" d
    ensure_arg src "$src" "Local folder, .zip or GitHub repo: " || { log_error "No source given."; return 1; }
    if [ -d "$src" ]; then
        cd "$src" || return 1
        log_success "Using local project: $(pwd)"
    elif [ -f "$src" ] && [[ "$src" == *.zip ]]; then
        d="$WORKSPACE/$(basename "${src%.zip}")"
        mkdir -p "$d" && cp -f "$src" "$d/" && cd "$d" || return 1
        action_unzip_to_root "$(basename "$src")" true
    else
        action_clone "$src"
    fi
}

# ==============================================================================
# ZIP -> ROOT
# ==============================================================================
extract_zip() {  # extract_zip zipfile destdir
    if   command -v unzip   >/dev/null 2>&1; then unzip -o -q "$1" -d "$2"
    elif command -v bsdtar  >/dev/null 2>&1; then bsdtar -xf "$1" -C "$2"
    elif command -v python3 >/dev/null 2>&1; then python3 -m zipfile -e "$1" "$2"
    elif command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command "Expand-Archive -Force -Path '$1' -DestinationPath '$2'"
    else log_error "Need one of: unzip, bsdtar, python3"; return 1; fi
}

action_unzip_to_root() {
    local pattern="${1:-*.zip}" keep="${2:-false}" f newest="" tmp src n only
    shopt -s nullglob
    for f in $pattern ./*/$pattern; do          # newest match, depth <= 2
        [ -f "$f" ] || continue
        if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
    done
    shopt -u nullglob
    [ -n "$newest" ] || { log_error "No zip file found matching: $pattern"; return 1; }

    log_info "Extracting $newest into the current directory..."
    tmp=$(mktemp -d "./.repodir_unzip.XXXXXX") || { log_error "Cannot create temp dir."; return 1; }
    if ! extract_zip "$newest" "$tmp"; then rm -rf "$tmp"; return 1; fi

    src="$tmp"   # GitHub-style zips wrap everything in one folder: flatten it
    n=$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    if [ "$n" -eq 1 ]; then
        only=$(find "$tmp" -mindepth 1 -maxdepth 1)
        [ -d "$only" ] && src="$only"
    fi
    cp -a "$src"/. ./ || { log_error "Copy failed."; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"

    if [ "$keep" = "false" ] && [ -f "$newest" ]; then rm -f "$newest"; log_info "Removed source archive."; fi
    log_success "Unzip complete."
}

# ==============================================================================
# OPENCODE
# ==============================================================================
action_install_opencode() {
    export PATH="$HOME/.opencode/bin:$BIN_DIR:$PATH"
    if command -v opencode >/dev/null 2>&1; then return 0; fi
    need curl || return 1
    log_info "Installing OpenCode..."
    if ! curl -fsSL "$OPENCODE_INSTALL_URL" | bash; then
        log_error "OpenCode install failed (network? try: $OPENCODE_INSTALL_URL)"
        return 1
    fi
    export PATH="$HOME/.opencode/bin:$PATH"
    command -v opencode >/dev/null 2>&1 || { log_error "OpenCode installed but not on PATH; restart your shell."; return 1; }
    log_success "OpenCode installed."
}

action_opencode() { action_install_opencode || return 1; opencode; }

# oc_run "prompt" : non-interactive OpenCode run (respects AI_MODEL / --model)
oc_run() {
    if [ -n "$AI_MODEL" ]; then opencode run -m "$AI_MODEL" "$1"; else opencode run "$1"; fi
}

# ==============================================================================
# INSTALL / UPDATE / UNINSTALL / DOCTOR / COMPLETION
# ==============================================================================
completion_script() {
cat <<EOF
# repodir completion (bash + zsh)
if [ -n "\${ZSH_VERSION:-}" ]; then
  autoload -U +X compinit 2>/dev/null && compinit 2>/dev/null
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null
fi
complete -W "$FLAGS_ALL" repodir
EOF
}

rc_strip() {  # remove our marker block from an rc file
    local rc="$1" tmp
    [ -f "$rc" ] && grep -qF "$RC_START" "$rc" || return 0
    tmp=$(mktemp) || return 1
    awk -v s="$RC_START" -v e="$RC_END" '$0==s{skip=1;next} $0==e{skip=0;next} !skip' "$rc" > "$tmp" && cat "$tmp" > "$rc"
    rm -f "$tmp"
}

install_system() {
    mkdir -p "$ROOT_DIR" "$BIN_DIR" || return 1
    local dest="$ROOT_DIR/repodir" src="${BASH_SOURCE[0]:-}" rc
    # Piped from curl => there is no local file, so download a copy.
    if [ -n "$src" ] && [ -f "$src" ] && [ -r "$src" ]; then
        [ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" = "$dest" ] || cp -f "$src" "$dest"
    else
        need curl || return 1
        curl -fsSL "$SELF_URL" -o "$dest" || { log_error "Could not download $SELF_URL"; return 1; }
    fi
    chmod +x "$dest"
    ln -sf "$dest" "$BIN_DIR/repodir"
    completion_script > "$ROOT_DIR/completion.bash"

    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do rc_strip "$rc"; done
    case "${SHELL:-}" in
        */zsh)  rc="$HOME/.zshrc" ;;
        */bash) if [ "$OS_NAME" = macos ] && [ ! -f "$HOME/.bashrc" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
        *)      rc="$HOME/.profile" ;;
    esac
    printf '\n%s\nexport PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"\n[ -f "%s/completion.bash" ] && . "%s/completion.bash"\n%s\n' \
        "$RC_START" "$ROOT_DIR" "$ROOT_DIR" "$RC_END" >> "$rc"
    log_success "Installed: $BIN_DIR/repodir  (PATH + tab-completion added to $rc; open a new shell, then run: repodir)"
}

action_checksum() {  # print sha256 of the installed/running script (publish as repodir.sh.sha256)
    local f="${BASH_SOURCE[0]:-}"
    [ -f "$f" ] || f="$ROOT_DIR/repodir"
    [ -f "$f" ] || { log_error "No local script file to hash."; return 1; }
    printf '%s  repodir.sh\n' "$(sha256_of "$f")"
}

action_update() {
    need curl || return 1
    local tmp sum dest="$ROOT_DIR/repodir" want got
    tmp=$(mktemp) || return 1; sum=$(mktemp) || return 1
    log_info "Fetching latest version from $SELF_URL"
    if ! curl -fsSL -m 30 "$SELF_URL" -o "$tmp"; then rm -f "$tmp" "$sum"; log_error "Download failed."; return 1; fi
    if ! bash -n "$tmp" 2>/dev/null; then rm -f "$tmp" "$sum"; log_error "Downloaded script failed syntax check; keeping current version."; return 1; fi

    if curl -fsSL -m 15 "$CHECKSUM_URL" -o "$sum" 2>/dev/null && [ -s "$sum" ]; then
        want=$(awk '{print $1; exit}' "$sum"); got=$(sha256_of "$tmp")
        if [ -z "$got" ]; then
            log_warn "No sha256 tool available; cannot verify."
            confirm_or_yes "Install without verification?" n || { rm -f "$tmp" "$sum"; return 1; }
        elif [ "$want" != "$got" ]; then
            rm -f "$tmp" "$sum"
            log_error "Checksum mismatch (expected ${want:0:12}..., got ${got:0:12}...). GitHub Pages may still be caching; retry in a few minutes."
            return 1
        else
            log_success "SHA-256 verified."
        fi
    else
        log_warn "No checksum published at $CHECKSUM_URL"
        confirm_or_yes "Install without verification?" n || { rm -f "$tmp" "$sum"; return 1; }
    fi
    mkdir -p "$ROOT_DIR"; cat "$tmp" > "$dest"; chmod +x "$dest"
    ln -sf "$dest" "$BIN_DIR/repodir" 2>/dev/null
    completion_script > "$ROOT_DIR/completion.bash" 2>/dev/null
    rm -f "$tmp" "$sum"
    log_success "Updated to v$(grep -m1 '^VERSION=' "$dest" | cut -d'"' -f2)"
}

# Once a day: tell the user if a newer version is published.
check_update_notice() {
    [ "$INTERACTIVE" = true ] && command -v curl >/dev/null 2>&1 || return 0
    [ -n "${REPODIR_NO_UPDATE_CHECK:-}" ] && return 0
    local stamp="$ROOT_DIR/.lastcheck" now last remote
    now=$(date +%s); last=0
    [ -f "$stamp" ] && last=$(cat "$stamp" 2>/dev/null)
    [ $((now - ${last:-0})) -lt 86400 ] && return 0
    mkdir -p "$ROOT_DIR"; echo "$now" > "$stamp"
    remote=$(curl -fsSL -m 3 "$SELF_URL" 2>/dev/null | grep -m1 '^VERSION=' | cut -d'"' -f2)
    if [ -n "$remote" ] && ver_gt "$remote" "$VERSION"; then
        log_warn "repodir v$remote is available (you have v$VERSION). Run: repodir --update"
    fi
    return 0
}

action_uninstall() {
    confirm_or_yes "Remove repodir, its config, tokens, profiles and reports?" n || { log_info "Cancelled."; return 0; }
    rm -f "$BIN_DIR/repodir"
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do rc_strip "$rc"; done
    rm -rf "$ROOT_DIR"
    log_success "repodir removed. (Cloned repos in $WORKSPACE were left untouched.)"
}

action_doctor() {
    local t
    echo "repodir v$VERSION | bash ${BASH_VERSION} | OS: $OS_NAME ($ARCH) | profile: $PROFILE"
    echo "Core:"
    for t in git curl unzip python3 opencode gh fzf; do
        if command -v "$t" >/dev/null 2>&1; then printf '  [ok]      %s\n' "$t"; else printf '  [missing] %s\n' "$t"; fi
    done
    echo "Build toolchains (only needed for the project types you build):"
    for t in node npm go cargo rustup java gradle mvn flutter dotnet cmake make zig docker bun; do
        if command -v "$t" >/dev/null 2>&1; then printf '  [ok]      %s\n' "$t"; else printf '  [missing] %s\n' "$t"; fi
    done
    if android_sdk_dir >/dev/null 2>&1; then echo "  [ok]      Android SDK ($(android_sdk_dir))"; else echo "  [missing] Android SDK (ANDROID_HOME)"; fi
    [ -n "$GPH_KEY" ] && echo "  [ok]      GitHub token configured" || echo "  [info]    GitHub token not set (optional)"
    [ "$INTERACTIVE" = true ] && echo "  [ok]      interactive terminal" || echo "  [info]    no terminal (headless mode only)"
    [ -x "$BIN_DIR/repodir" ] && echo "  [ok]      installed at $BIN_DIR/repodir" || echo "  [info]    not installed (run: --install)"
}

# ==============================================================================
# AUDIT ENGINE
# ==============================================================================
SECRET_REGEX='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|passwd|password|token)[^A-Za-z0-9]{1,4}[A-Za-z0-9/+_-]{16,}'

# Prints "file:line  abc123...[redacted]" - never the full secret.
scan_secrets_raw() {
    grep -rIEno -i --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=venv \
        -e "$SECRET_REGEX" "${1:-.}" 2>/dev/null |
    awk -F: '{ m=$0; sub(/^[^:]*:[^:]*:/, "", m); printf "%s:%s  %s...[redacted]\n", $1, $2, substr(m,1,6) }'
}

# Scan ADDED lines of a unified diff on stdin (used by history + diff audits).
# Input: diff with -U0. Output: "<tag>:file  abc123...[redacted]"
scan_diff_added() {
    local tag="$1" f l m
    awk '/^\+\+\+ /{f=substr($0,7);next} /^\+/{print f "\t" substr($0,2)}' |
    while IFS=$'\t' read -r f l; do
        m=$(printf '%s' "$l" | grep -Eio -e "$SECRET_REGEX" | head -n1)
        [ -n "$m" ] && printf '%s:%s  %s...[redacted]\n' "$tag" "$f" "${m:0:6}"
    done
}

scan_history_raw() {
    local dir="$1" h commits
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    commits=$(git -C "$dir" log --all -i -G"$SECRET_REGEX" --max-count="${REPODIR_HISTORY_LIMIT:-300}" --pretty=format:'%h' 2>/dev/null)
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        git -C "$dir" show --format= -U0 --no-color "$h" 2>/dev/null | scan_diff_added "$h"
    done <<< "$commits"
}

action_scan_secrets() {
    local dir="${1:-.}" hits count
    log_info "Scanning working tree for hard-coded secrets: $dir"
    hits=$(scan_secrets_raw "$dir"); count=$(count_lines "$hits"); SECRET_HITS=$count
    if [ "$count" -gt 0 ]; then
        log_warn "$count potential secret(s) found:"
        printf '%s\n' "$hits" | head -n 50
        [ "$count" -gt 50 ] && echo "... and $((count - 50)) more"
        return 2
    fi
    log_success "No obvious secrets found."
}

action_history() {
    local dir="${1:-.}" hits count
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found."; return 1; }
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { log_error "Not a git repository."; return 1; }
    log_info "Scanning git history (last ${REPODIR_HISTORY_LIMIT:-300} matching commits, all branches)... Deleted keys are still exposed in history."
    hits=$(scan_history_raw "$dir" | sort -u); count=$(count_lines "$hits")
    if [ "$count" -gt 0 ]; then
        log_warn "$count potential secret(s) in history (commit:file):"
        printf '%s\n' "$hits" | head -n 50
        echo "Fix: rotate the credential FIRST, then purge with git-filter-repo or BFG."
        return 2
    fi
    log_success "No secrets found in scanned history."
}

# ---- dependency vulnerabilities ----------------------------------------------
audit_deps() {
    local dir="$1" n=0 c h m l out osv="" osv_n=-1 osv_chk=0 any=false line
    if [ -f "$dir/package-lock.json" ] && command -v npm >/dev/null 2>&1; then
        any=true; out=$(cd "$dir" && npm audit --json 2>/dev/null)
        if [[ "$out" == *'"vulnerabilities"'* ]]; then
            c=$(printf '%s' "$out" | grep -o '"critical": *[0-9]*' | tail -1 | grep -o '[0-9]*$')
            h=$(printf '%s' "$out" | grep -o '"high": *[0-9]*' | tail -1 | grep -o '[0-9]*$')
            m=$(printf '%s' "$out" | grep -o '"moderate": *[0-9]*' | tail -1 | grep -o '[0-9]*$')
            l=$(printf '%s' "$out" | grep -o '"low": *[0-9]*' | tail -1 | grep -o '[0-9]*$')
            echo "- npm audit: critical=${c:-0} high=${h:-0} moderate=${m:-0} low=${l:-0}"
            n=$((n + ${c:-0} + ${h:-0} + ${m:-0} + ${l:-0}))
        else echo "- npm audit: unavailable (offline or registry error)"; fi
    fi
    if [ -f "$dir/requirements.txt" ] && command -v pip-audit >/dev/null 2>&1; then
        any=true; out=$(cd "$dir" && pip-audit -r requirements.txt 2>&1)
        c=$(printf '%s\n' "$out" | grep -Ec 'PYSEC-|GHSA-|CVE-'); echo "- pip-audit: $c advisory line(s)"; n=$((n + c))
    fi
    if [ -f "$dir/go.mod" ] && command -v govulncheck >/dev/null 2>&1; then
        any=true; out=$(cd "$dir" && govulncheck ./... 2>&1)
        c=$(printf '%s\n' "$out" | grep -c '^Vulnerability #'); echo "- govulncheck: $c vulnerabilit(ies)"; n=$((n + c))
    fi
    if [ -f "$dir/Cargo.lock" ] && command -v cargo >/dev/null 2>&1 && cargo audit --version >/dev/null 2>&1; then
        any=true; out=$(cd "$dir" && cargo audit 2>&1)
        c=$(printf '%s\n' "$out" | grep -c '^ID:'); echo "- cargo audit: $c advisory(ies)"; n=$((n + c))
    fi

    if command -v python3 >/dev/null 2>&1; then
        osv=$(python3 - "$dir" <<'PY' 2>/dev/null
import json, os, re, sys, urllib.request
root = sys.argv[1]
pk = {}
SKIP = {'.git', 'node_modules', '.venv', 'venv', 'vendor', 'target', 'dist', 'build'}
def add(eco, name, ver, src):
    pk.setdefault((eco, name, ver), src)
for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in SKIP]
    if dp[len(root):].count(os.sep) > 3:
        dn[:] = []
        continue
    for f in fn:
        p = os.path.join(dp, f); rel = os.path.relpath(p, root)
        try:
            if f == 'requirements.txt':
                for l in open(p, errors='ignore'):
                    m = re.match(r'\s*([A-Za-z0-9_.\-]+)\s*==\s*([A-Za-z0-9_.\-]+)', l)
                    if m: add('PyPI', m.group(1), m.group(2), rel)
            elif f == 'package-lock.json':
                d = json.load(open(p))
                for k, v in (d.get('packages') or {}).items():
                    if 'node_modules/' in k and isinstance(v, dict) and v.get('version') and not v.get('link'):
                        add('npm', k.split('node_modules/')[-1], v['version'], rel)
                def walk(deps):
                    for n, v in (deps or {}).items():
                        if isinstance(v, dict):
                            if v.get('version'): add('npm', n, v['version'], rel)
                            walk(v.get('dependencies'))
                if not d.get('packages'): walk(d.get('dependencies'))
            elif f == 'go.mod':
                for l in open(p, errors='ignore'):
                    m = re.match(r'\s*(?:require\s+)?([A-Za-z0-9_.\-/~]+\.[A-Za-z0-9_.\-/~]+)\s+v(\d[^\s]*)', l)
                    if m: add('Go', m.group(1), m.group(2), rel)
            elif f == 'Cargo.lock':
                t = open(p, errors='ignore').read()
                for m in re.finditer(r'name = "([^"]+)"\nversion = "([^"]+)"', t):
                    add('crates.io', m.group(1), m.group(2), rel)
        except Exception:
            pass
keys = list(pk)
if not keys:
    print('@@OSVSTAT 0 0'); sys.exit(0)
vuln = {}
try:
    for i in range(0, len(keys), 500):
        chunk = keys[i:i + 500]
        body = json.dumps({'queries': [{'package': {'ecosystem': e, 'name': n}, 'version': v} for e, n, v in chunk]}).encode()
        req = urllib.request.Request('https://api.osv.dev/v1/querybatch', body, {'Content-Type': 'application/json'})
        res = json.load(urllib.request.urlopen(req, timeout=25))
        for k, r in zip(chunk, res.get('results', [])):
            ids = [x['id'] for x in (r.get('vulns') or [])]
            if ids: vuln[k] = ids
except Exception as e:
    print('@@OSVFAIL %s' % type(e).__name__); sys.exit(0)
for (e, n, v), ids in list(vuln.items())[:40]:
    print('- OSV: %s %s@%s: %s (%s)' % (e, n, v, ', '.join(ids[:4]), pk[(e, n, v)]))
if len(vuln) > 40: print('- OSV: ... and %d more' % (len(vuln) - 40))
print('@@OSVSTAT %d %d' % (len(vuln), len(keys)))
PY
)
        while IFS= read -r line; do
            case "$line" in
                "@@OSVSTAT "*) read -r _ osv_n osv_chk <<< "$line" ;;
                "@@OSVFAIL "*) echo "- OSV.dev lookup failed (${line#@@OSVFAIL }) - offline or blocked" ;;
                "") ;;
                *) echo "$line" ;;
            esac
        done <<< "$osv"
        if [ "$osv_n" -ge 0 ] && [ "$osv_chk" -gt 0 ]; then
            any=true; echo "- OSV.dev: checked $osv_chk pinned package(s), $osv_n vulnerable"
        fi
    fi
    [ "$any" = true ] || echo "- no dependency results (no supported manifests, or lookup failed/offline)"
    if [ "$osv_n" -ge 0 ]; then echo "@@COUNT $osv_n"; else echo "@@COUNT $n"; fi
}

action_deps() {
    local dir="${1:-.}" out
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found."; return 1; }
    log_info "Checking dependencies for known vulnerabilities..."
    out=$(audit_deps "$dir")
    printf '%s\n' "$out" | grep -v '^@@COUNT '
    local n; n=$(printf '%s\n' "$out" | sed -n 's/^@@COUNT //p' | tail -1)
    [ "${n:-0}" -gt 0 ] && { log_warn "${n} vulnerable dependency finding(s)."; return 2; }
    log_success "No known vulnerabilities detected."
}

action_outdated() {
    log_info "Checking for outdated dependencies..."
    [ -f package.json ] && command -v npm >/dev/null 2>&1 && { echo "== npm =="; npm outdated 2>/dev/null | head -n 40; }
    [ -f requirements.txt ] || [ -f pyproject.toml ] && command -v pip >/dev/null 2>&1 && { echo "== pip =="; pip list --outdated 2>/dev/null | head -n 40; }
    [ -f go.mod ] && command -v go >/dev/null 2>&1 && { echo "== go =="; go list -u -m all 2>/dev/null | grep '\[' | head -n 40; }
    [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1 && { echo "== cargo =="; cargo outdated 2>/dev/null | head -n 40; }
    return 0
}

# ---- CI / Docker / compose / Terraform / Kubernetes checks ------------------
fnd() { printf -- '- [%s] %s: %s\n' "$1" "${2#./}" "$3"; }

chk_pat() {  # chk_pat SEV "msg" REGEX files...
    local sev="$1" msg="$2" rx="$3" f n; shift 3
    for f in "$@"; do
        n=$(grep -Eic -e "$rx" "$f" 2>/dev/null)
        if [ "${n:-0}" -gt 0 ]; then fnd "$sev" "$f" "$msg"; fi
    done
}

extra_checks() {
    local dir="$1" f unp files
    # GitHub Actions
    while IFS= read -r f; do
        unp=$(grep -E '^[[:space:]-]*uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@' "$f" 2>/dev/null | grep -Evc '@[0-9a-f]{40}([[:space:]]|$)')
        [ "${unp:-0}" -gt 0 ] && fnd LOW "$f" "$unp action(s) not pinned to a commit SHA"
        grep -qE '(^|[[:space:],:[])pull_request_target' "$f" 2>/dev/null && fnd MED "$f" "uses pull_request_target (never check out untrusted PR code with it)"
        grep -qE '^permissions:' "$f" 2>/dev/null || fnd LOW "$f" "no top-level permissions block (token gets default scopes)"
        grep -qE '\$\{\{[[:space:]]*github\.(event\.(issue|pull_request|comment|review|head_commit|commits)|head_ref)' "$f" 2>/dev/null && fnd HIGH "$f" "possible script injection via untrusted github context"
        grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo )?(ba)?sh' "$f" 2>/dev/null && fnd MED "$f" "pipes a download into a shell"
    done < <(find "$dir/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)

    # Dockerfiles
    while IFS= read -r f; do
        awk -v F="${f#./}" '
            toupper($1)=="FROM" { seen=1; i=2; if ($2 ~ /^--/) i=3; img=$i
                if (!(img in al) && img != "scratch" && img !~ /^\$/) {
                    if (img ~ /:latest$/) printf "- [MED] %s: base image %s uses the latest tag\n", F, img
                    else if (img !~ /[:@]/) printf "- [MED] %s: base image %s has no version tag\n", F, img }
                if (toupper($(i+1))=="AS") al[$(i+2)]=1 }
            toupper($1)=="USER" { u=1 }
            END { if (seen && !u) printf "- [MED] %s: no USER instruction (container runs as root)\n", F }' "$f"
        chk_pat HIGH "secret-looking value in ENV/ARG" '^(ENV|ARG)[[:space:]]+[A-Za-z_]*(PASSWORD|SECRET|TOKEN|API_?KEY)[A-Za-z_]*[= ][^$[:space:]]' "$f"
        chk_pat MED  "pipes a download into a shell" '(curl|wget)[^|]*\|[[:space:]]*(sudo )?(ba)?sh' "$f"
        chk_pat LOW  "ADD from remote URL (use COPY/curl with checksum)" '^ADD[[:space:]]+https?://' "$f"
        chk_pat LOW  "chmod 777" 'chmod[[:space:]]+(-R[[:space:]]+)?777' "$f"
    done < <(find "$dir" -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) "${PRUNE[@]}" 2>/dev/null)

    # docker-compose
    files=(); while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -type f \( -name 'docker-compose*.y*ml' -o -name 'compose*.y*ml' \) "${PRUNE[@]}" 2>/dev/null)
    if [ ${#files[@]} -gt 0 ]; then
        chk_pat HIGH "privileged container" '^[[:space:]]*privileged:[[:space:]]*true' "${files[@]}"
        chk_pat HIGH "mounts the Docker socket" '/var/run/docker\.sock' "${files[@]}"
        chk_pat MED  "host network mode" '^[[:space:]]*network_mode:[[:space:]]*"?host' "${files[@]}"
        chk_pat MED  "inline credential in environment" '(password|secret|token|api_?key)[A-Za-z_]*[:=][[:space:]]*[A-Za-z0-9]' "${files[@]}"
    fi

    # Terraform
    files=(); while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -type f -name '*.tf' "${PRUNE[@]}" 2>/dev/null)
    if [ ${#files[@]} -gt 0 ]; then
        chk_pat MED  "open to the world (0.0.0.0/0)" '0\.0\.0\.0/0' "${files[@]}"
        chk_pat HIGH "public-read ACL" 'acl[[:space:]]*=[[:space:]]*"public-read' "${files[@]}"
        chk_pat HIGH "publicly accessible resource" 'publicly_accessible[[:space:]]*=[[:space:]]*true' "${files[@]}"
        chk_pat MED  "encryption disabled" 'encrypted[[:space:]]*=[[:space:]]*false' "${files[@]}"
    fi

    # Kubernetes manifests
    files=()
    while IFS= read -r f; do
        grep -qE '^kind:[[:space:]]*(Deployment|Pod|StatefulSet|DaemonSet|Job|CronJob|Secret)' "$f" 2>/dev/null && files+=("$f")
    done < <(find "$dir" -type f \( -name '*.yaml' -o -name '*.yml' \) -not -path '*/.github/*' "${PRUNE[@]}" 2>/dev/null)
    if [ ${#files[@]} -gt 0 ]; then
        chk_pat HIGH "privileged container" '^[[:space:]]*privileged:[[:space:]]*true' "${files[@]}"
        chk_pat MED  "hostNetwork enabled" '^[[:space:]]*hostNetwork:[[:space:]]*true' "${files[@]}"
        chk_pat MED  "runs as root (runAsUser: 0)" '^[[:space:]]*runAsUser:[[:space:]]*0' "${files[@]}"
        chk_pat MED  "allowPrivilegeEscalation: true" 'allowPrivilegeEscalation:[[:space:]]*true' "${files[@]}"
        chk_pat LOW  "image uses :latest" 'image:[[:space:]]*[^[:space:]]+:latest' "${files[@]}"
        chk_pat MED  "Secret manifest with inline data committed" '^kind:[[:space:]]*Secret' "${files[@]}"
    fi
}

# ---- misc collectors --------------------------------------------------------
detect_license() {
    local f="" x
    for x in LICENSE LICENSE.md LICENSE.txt COPYING; do [ -f "$1/$x" ] && { f="$1/$x"; break; }; done
    [ -n "$f" ] || { echo "none"; return; }
    if   grep -qi 'GNU AFFERO' "$f"; then echo AGPL
    elif grep -qi 'GNU LESSER' "$f"; then echo LGPL
    elif grep -qi 'GNU GENERAL PUBLIC' "$f"; then echo GPL
    elif grep -qi 'Apache License' "$f"; then echo Apache-2.0
    elif grep -qi 'Mozilla Public' "$f"; then echo MPL-2.0
    elif grep -qi 'MIT License\|Permission is hereby granted, free of charge' "$f"; then echo MIT
    elif grep -qi 'free and unencumbered' "$f"; then echo Unlicense
    elif grep -qi 'BSD' "$f"; then echo BSD
    elif grep -qi 'ISC License' "$f"; then echo ISC
    else echo "unrecognized"; fi
}

loc_stats() {
    find "$1" -type f "${PRUNE[@]}" \( -name '*.sh' -o -name '*.bash' -o -name '*.py' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.kts' -o -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' -o -name '*.cs' -o -name '*.rb' -o -name '*.php' -o -name '*.swift' -o -name '*.dart' -o -name '*.lua' -o -name '*.html' -o -name '*.css' -o -name '*.scss' -o -name '*.vue' -o -name '*.zig' \) -print0 2>/dev/null |
    xargs -0 wc -l 2>/dev/null |
    awk '
        BEGIN{ m["sh"]="Shell";m["bash"]="Shell";m["py"]="Python";m["js"]="JavaScript";m["jsx"]="JavaScript";m["ts"]="TypeScript";m["tsx"]="TypeScript";m["go"]="Go";m["rs"]="Rust";m["java"]="Java";m["kt"]="Kotlin";m["kts"]="Kotlin";m["c"]="C";m["h"]="C/C++ header";m["cpp"]="C++";m["hpp"]="C++";m["cs"]="C#";m["rb"]="Ruby";m["php"]="PHP";m["swift"]="Swift";m["dart"]="Dart";m["lua"]="Lua";m["html"]="HTML";m["css"]="CSS";m["scss"]="CSS";m["vue"]="Vue";m["zig"]="Zig" }
        $NF=="total" {next}
        { n=$1; f=$0; sub(/^ *[0-9]+ /,"",f); k=split(f,a,"."); e=a[k]; l=(e in m)?m[e]:e; s[l]+=n }
        END{ for (l in s) printf "%d\t%s\n", s[l], l }' |
    sort -rn | head -10 | awk -F'\t' '{printf "    %8d  %s\n",$1,$2}'
}

has_any() { local d="$1" x; shift; for x in "$@"; do [ -e "$d/$x" ] && return 0; done; return 1; }

# ---- GitHub API helpers ------------------------------------------------------
gh_api() {  # gh_api /path -> JSON on stdout
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh api "$1" 2>/dev/null
    elif command -v curl >/dev/null 2>&1; then
        if [ -n "$GPH_KEY" ]; then
            printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github+json"\nurl = "https://api.github.com%s"\n' "$GPH_KEY" "$1" |
                curl -fsSL -m 15 -K - 2>/dev/null
        else
            curl -fsSL -m 15 -H 'Accept: application/vnd.github+json' "https://api.github.com$1" 2>/dev/null
        fi
    fi
}
jget() {  # jget key  (first top-level-ish scalar from JSON on stdin)
    grep -o "\"$1\": *\(\"[^\"]*\"\|[0-9a-z]*\)" | head -1 | sed 's/^[^:]*: *//; s/"//g'
}

github_section() {  # GitHub facts for the audit report
    local slug="$1" j a p
    [ -n "$slug" ] || return 0
    j=$(gh_api "/repos/$slug")
    [ -n "$j" ] || { echo "- GitHub API unavailable for $slug (offline / private without token)"; return 0; }
    echo "- Repo: $slug  | stars: $(printf '%s' "$j" | jget stargazers_count)  forks: $(printf '%s' "$j" | jget forks_count)  open issues+PRs: $(printf '%s' "$j" | jget open_issues_count)"
    echo "- Visibility: $(printf '%s' "$j" | jget visibility)  | archived: $(printf '%s' "$j" | jget archived)  | last push: $(printf '%s' "$j" | jget pushed_at)"
    p=$(gh_api "/repos/$slug/pulls?state=open&per_page=100" | grep -o '"merge_commit_sha"' | wc -l | tr -d ' ')
    echo "- Open pull requests (approx): ${p:-0}"
    a=$(gh_api "/repos/$slug/dependabot/alerts?state=open&per_page=100")
    if [ -n "$a" ] && [[ "$a" != *'"message"'* ]]; then echo "- Open Dependabot alerts: $(printf '%s' "$a" | grep -o '"ghsa_id"' | wc -l | tr -d ' ')"
    else echo "- Dependabot alerts: not accessible (needs token with security_events/alerts access)"; fi
}

action_gh_info() {
    local slug="${1:-$(repo_slug "$(git remote get-url origin 2>/dev/null)")}"
    [ -n "$slug" ] || slug=$(repo_slug "$TARGET_REPO")
    [ -n "$slug" ] || { log_error "Not a GitHub repo. Use: gh-info owner/repo"; return 1; }
    github_section "$slug"
}

# ---- collect + score ---------------------------------------------------------
collect_audit() {
    local dir="$1" out
    AUD_DIR="$dir"; AUD_NAME=$(basename "$dir")
    AUD_FILES=$(find "$dir" -type f "${PRUNE[@]}" 2>/dev/null | wc -l | tr -d ' ')
    AUD_SIZE_KB=$(du -sk "$dir" 2>/dev/null | cut -f1)
    AUD_HITS=$(scan_secrets_raw "$dir"); AUD_SECRETS=$(count_lines "$AUD_HITS"); SECRET_HITS=$AUD_SECRETS
    AUD_RISKY=$(find "$dir" -type f \( -name '.env' -o -name '.env.*' -o -name 'id_rsa' -o -name 'id_ed25519' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name '*.keystore' -o -name '*.jks' \) \
                ! -name '*.example' ! -name '*.sample' "${PRUNE[@]}" 2>/dev/null)
    AUD_RISKY_N=$(count_lines "$AUD_RISKY")
    AUD_TODO=$(grep -rIE --exclude-dir=.git --exclude-dir=node_modules 'TODO|FIXME|HACK|XXX' "$dir" 2>/dev/null | wc -l | tr -d ' ')
    AUD_LICENSE=$(detect_license "$dir")
    AUD_LOC=$(loc_stats "$dir")
    AUD_LARGE=$(find "$dir" -type f -size +5M "${PRUNE[@]}" -exec du -k {} + 2>/dev/null | sort -rn | head -5 | awk -F'\t' '{printf "- %s (%s KB)\n", $2, $1}')
    AUD_LFS="no"; grep -qs 'filter=lfs' "$dir/.gitattributes" && AUD_LFS="yes"
    AUD_EXTRA=$(extra_checks "$dir")
    AUD_EXTRA_HIGH=$(printf '%s\n' "$AUD_EXTRA" | grep -c '^- \[HIGH\]')
    AUD_EXTRA_MED=$(printf '%s\n' "$AUD_EXTRA" | grep -c '^- \[MED\]')
    AUD_EXTRA_LOW=$(printf '%s\n' "$AUD_EXTRA" | grep -c '^- \[LOW\]')
    AUD_EXTRA_N=$((AUD_EXTRA_HIGH + AUD_EXTRA_MED + AUD_EXTRA_LOW))

    # hygiene (1 = missing)
    H_README=1;  has_any "$dir" README.md README README.rst readme.md && H_README=0
    H_LICENSE=1; has_any "$dir" LICENSE LICENSE.md LICENSE.txt COPYING && H_LICENSE=0
    H_IGNORE=1;  has_any "$dir" .gitignore && H_IGNORE=0
    H_SEC=1;     has_any "$dir" SECURITY.md .github/SECURITY.md && H_SEC=0
    H_CI=1;      has_any "$dir" .github/workflows .gitlab-ci.yml .circleci Jenkinsfile .travis.yml && H_CI=0
    AUD_HYG_MISS=$((H_README + H_LICENSE + H_IGNORE + H_SEC + H_CI))

    AUD_HIST=""; AUD_HIST_N=0; AUD_DEPS=""; AUD_VULN_N=0; AUD_GH=""
    if [ "$AUDIT_FULL" = true ]; then
        AUD_HIST=$(scan_history_raw "$dir" | sort -u); AUD_HIST_N=$(count_lines "$AUD_HIST")
        out=$(audit_deps "$dir")
        AUD_VULN_N=$(printf '%s\n' "$out" | sed -n 's/^@@COUNT //p' | tail -1); AUD_VULN_N=${AUD_VULN_N:-0}
        AUD_DEPS=$(printf '%s\n' "$out" | grep -v '^@@COUNT ')
        AUD_GH=$(github_section "$(repo_slug "$(git -C "$dir" remote get-url origin 2>/dev/null)")")
    fi
    compute_score
}

compute_score() {
    local s=100 d
    d=$(cap $((AUD_SECRETS * 10)) 40); s=$((s - d))
    d=$(cap $((AUD_HIST_N * 5)) 15);   s=$((s - d))
    d=$(cap $((AUD_RISKY_N * 5)) 15);  s=$((s - d))
    d=$(cap $((AUD_VULN_N * 3)) 20);   s=$((s - d))
    d=$(cap $((AUD_EXTRA_HIGH * 4 + AUD_EXTRA_MED * 2 + AUD_EXTRA_LOW)) 15); s=$((s - d))
    d=$(cap $((H_README * 4 + H_LICENSE * 3 + H_IGNORE * 3 + H_SEC * 2 + H_CI * 3)) 15); s=$((s - d))
    [ "$s" -lt 0 ] && s=0
    AUD_SCORE=$s
    if   [ "$s" -ge 90 ]; then AUD_GRADE=A
    elif [ "$s" -ge 80 ]; then AUD_GRADE=B
    elif [ "$s" -ge 70 ]; then AUD_GRADE=C
    elif [ "$s" -ge 60 ]; then AUD_GRADE=D
    else AUD_GRADE=F; fi
}

audit_summary_line() {
    printf 'repodir audit %s: grade %s (%s/100) | secrets %s | history %s | vulns %s | CI/IaC findings %s' \
        "$AUD_NAME" "$AUD_GRADE" "$AUD_SCORE" "$AUD_SECRETS" "$AUD_HIST_N" "$AUD_VULN_N" "$AUD_EXTRA_N"
}

# ---- baseline (compare against a previous audit) -----------------------------
norm_hits() { printf '%s\n' "$1" | sed -E 's/^([^:]*):[0-9]+  /\1  /' | grep -v '^$' | sort -u; }

save_baseline() {
    mkdir -p "$BASE_DIR" || return 1
    printf 'DATE=%s\nSCORE=%s\nSECRETS=%s\nHIST=%s\nVULNS=%s\nEXTRA=%s\nFILES=%s\n' \
        "$(date +%F)" "$AUD_SCORE" "$AUD_SECRETS" "$AUD_HIST_N" "$AUD_VULN_N" "$AUD_EXTRA_N" "$AUD_FILES" > "$BASE_DIR/$AUD_NAME.base"
    norm_hits "$AUD_HITS" > "$BASE_DIR/$AUD_NAME.secrets"
    log_success "Baseline saved for $AUD_NAME (future audits will show the delta)."
}

baseline_section() {
    local b="$BASE_DIR/$AUD_NAME.base" k v B_DATE="" B_SCORE=0 B_SECRETS=0 B_HIST=0 B_VULNS=0 B_EXTRA=0 new fixed
    [ -f "$b" ] || return 0
    while IFS='=' read -r k v; do
        case "$k" in DATE) B_DATE="$v";; SCORE) B_SCORE="$v";; SECRETS) B_SECRETS="$v";; HIST) B_HIST="$v";; VULNS) B_VULNS="$v";; EXTRA) B_EXTRA="$v";; esac
    done < "$b"
    echo "## Compared to baseline ($B_DATE)"
    printf -- '- Score: %s -> %s (%+d)\n' "$B_SCORE" "$AUD_SCORE" $((AUD_SCORE - B_SCORE))
    printf -- '- Secrets: %s -> %s (%+d)\n' "$B_SECRETS" "$AUD_SECRETS" $((AUD_SECRETS - B_SECRETS))
    printf -- '- History findings: %s -> %s (%+d)\n' "$B_HIST" "$AUD_HIST_N" $((AUD_HIST_N - B_HIST))
    printf -- '- Vulnerable deps: %s -> %s (%+d)\n' "$B_VULNS" "$AUD_VULN_N" $((AUD_VULN_N - B_VULNS))
    printf -- '- CI/IaC findings: %s -> %s (%+d)\n' "$B_EXTRA" "$AUD_EXTRA_N" $((AUD_EXTRA_N - B_EXTRA))
    if [ -f "$BASE_DIR/$AUD_NAME.secrets" ]; then
        new=$(comm -13 "$BASE_DIR/$AUD_NAME.secrets" <(norm_hits "$AUD_HITS"))
        fixed=$(comm -23 "$BASE_DIR/$AUD_NAME.secrets" <(norm_hits "$AUD_HITS"))
        [ -n "$new" ]   && { echo "- NEW secret findings:";   printf '%s\n' "$new"   | sed 's/^/    /'; }
        [ -n "$fixed" ] && { echo "- Fixed since baseline:";  printf '%s\n' "$fixed" | sed 's/^/    /'; }
    fi
    echo
}

# ---- renderers ----------------------------------------------------------------
render_md() {
    echo "# REPODIR audit: $AUD_NAME"
    echo
    echo "**Grade: $AUD_GRADE ($AUD_SCORE/100)**"
    echo
    echo "- Generated: $(date -u +%FT%TZ)"
    echo "- Path: \`$AUD_DIR\`"
    echo "- Tool: repodir v$VERSION | mode: $([ "$AUDIT_FULL" = true ] && echo full || echo quick)"
    echo
    baseline_section
    echo "## Overview"
    echo "- Files: $AUD_FILES | Size: ${AUD_SIZE_KB:-0} KB | License: $AUD_LICENSE"
    if git -C "$AUD_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "- Git branch: $(git -C "$AUD_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) | commits: $(git -C "$AUD_DIR" rev-list --count HEAD 2>/dev/null)"
        echo "- Last commit: $(git -C "$AUD_DIR" log -1 --format='%h %s (%an, %ar)' 2>/dev/null)"
        echo
        echo "### Top contributors"
        git -C "$AUD_DIR" shortlog -sn HEAD 2>/dev/null | head -5 | sed 's/^/    /'
    fi
    echo
    echo "## Code (lines per language)"
    [ -n "$AUD_LOC" ] && printf '%s\n' "$AUD_LOC" || echo "    (no recognised source files)"
    echo
    echo "## Largest files"
    find "$AUD_DIR" -type f "${PRUNE[@]}" -exec du -k {} + 2>/dev/null | sort -rn | head -5 | awk -F'\t' '{ printf "- %s (%s KB)\n", $2, $1 }'
    if [ -n "$AUD_LARGE" ]; then echo; echo "Files over 5 MB (Git LFS configured: $AUD_LFS):"; printf '%s\n' "$AUD_LARGE"; fi
    echo
    echo "## Hygiene"
    _hyg() { [ "$1" -eq 0 ] && echo "- [x] $2" || echo "- [ ] $2 (missing)"; }
    _hyg $H_README README; _hyg $H_LICENSE LICENSE; _hyg $H_IGNORE .gitignore; _hyg $H_SEC "SECURITY policy"; _hyg $H_CI "CI configuration"
    echo "- TODO/FIXME/HACK markers: $AUD_TODO"
    echo
    echo "## Sensitive files present: $AUD_RISKY_N"
    if [ "$AUD_RISKY_N" -gt 0 ]; then printf '%s\n' "$AUD_RISKY" | sed "s|^$AUD_DIR/|- |"; else echo "- none"; fi
    echo
    echo "## Potential hard-coded secrets: $AUD_SECRETS"
    if [ "$AUD_SECRETS" -gt 0 ]; then printf '%s\n' "$AUD_HITS" | head -n 100 | sed 's/^/    /'; else echo "- none detected"; fi
    echo
    echo "## CI / Docker / IaC findings: $AUD_EXTRA_N"
    if [ "$AUD_EXTRA_N" -gt 0 ]; then printf '%s\n' "$AUD_EXTRA"; else echo "- none detected"; fi
    if [ "$AUDIT_FULL" = true ]; then
        echo
        echo "## Secrets in git history: $AUD_HIST_N"
        if [ "$AUD_HIST_N" -gt 0 ]; then printf '%s\n' "$AUD_HIST" | head -n 100 | sed 's/^/    /'; echo "- Rotate these credentials, then purge history (git-filter-repo / BFG)."; else echo "- none detected"; fi
        echo
        echo "## Dependency vulnerabilities: $AUD_VULN_N"
        printf '%s\n' "$AUD_DEPS"
        if [ -n "$AUD_GH" ]; then echo; echo "## GitHub"; printf '%s\n' "$AUD_GH"; fi
    fi
}

render_json() {
    printf '{\n'
    printf '  "tool": "repodir", "version": "%s",\n' "$VERSION"
    printf '  "name": "%s", "path": "%s", "generated": "%s",\n' "$(json_esc "$AUD_NAME")" "$(json_esc "$AUD_DIR")" "$(date -u +%FT%TZ)"
    printf '  "mode": "%s", "score": %s, "grade": "%s",\n' "$([ "$AUDIT_FULL" = true ] && echo full || echo quick)" "$AUD_SCORE" "$AUD_GRADE"
    printf '  "files": %s, "size_kb": %s, "license": "%s", "todo_markers": %s,\n' "$AUD_FILES" "${AUD_SIZE_KB:-0}" "$(json_esc "$AUD_LICENSE")" "$AUD_TODO"
    printf '  "findings": {"secrets": %s, "history_secrets": %s, "sensitive_files": %s, "vulnerable_dependencies": %s, "ci_iac_high": %s, "ci_iac_medium": %s, "ci_iac_low": %s},\n' \
        "$AUD_SECRETS" "$AUD_HIST_N" "$AUD_RISKY_N" "$AUD_VULN_N" "$AUD_EXTRA_HIGH" "$AUD_EXTRA_MED" "$AUD_EXTRA_LOW"
    printf '  "hygiene_missing": {"readme": %s, "license": %s, "gitignore": %s, "security_policy": %s, "ci": %s},\n' \
        "$([ $H_README = 1 ] && echo true || echo false)" "$([ $H_LICENSE = 1 ] && echo true || echo false)" \
        "$([ $H_IGNORE = 1 ] && echo true || echo false)" "$([ $H_SEC = 1 ] && echo true || echo false)" "$([ $H_CI = 1 ] && echo true || echo false)"
    printf '  "secret_locations": ['
    local first=true line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$first" = true ] && first=false || printf ', '
        printf '"%s"' "$(json_esc "$line")"
    done <<< "$AUD_HITS"
    printf ']\n}\n'
}

render_html() {
    local color
    case "$AUD_GRADE" in A) color="#1a7f37";; B) color="#4c9a2a";; C) color="#bf8700";; D) color="#d4660b";; *) color="#cf222e";; esac
    cat <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>REPODIR audit: $(printf '%s' "$AUD_NAME" | html_esc)</title>
<style>
:root{--bg:#fff;--fg:#1f2328;--muted:#656d76;--card:#f6f8fa;--line:#d0d7de}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--card:#161b22;--line:#30363d}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:920px;margin:0 auto;padding:24px 16px}
h1{font-size:1.4rem;margin:0 0 4px}.sub{color:var(--muted);margin-bottom:20px}
.grade{display:inline-flex;align-items:baseline;gap:8px;background:$color;color:#fff;border-radius:12px;padding:10px 18px;font-size:2.4rem;font-weight:700}
.grade small{font-size:1rem;font-weight:500;opacity:.9}
table{border-collapse:collapse;width:100%;margin:20px 0;background:var(--card);border:1px solid var(--line);border-radius:8px;overflow:hidden}
td,th{padding:8px 12px;border-bottom:1px solid var(--line);text-align:left}tr:last-child td{border-bottom:0}
pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:14px;overflow-x:auto;font-size:13px;white-space:pre-wrap}
</style></head><body><main>
<h1>REPODIR audit: $(printf '%s' "$AUD_NAME" | html_esc)</h1>
<div class="sub">$(date -u +%FT%TZ) &middot; repodir v$VERSION &middot; $([ "$AUDIT_FULL" = true ] && echo full || echo quick) mode</div>
<div class="grade">$AUD_GRADE <small>$AUD_SCORE / 100</small></div>
<table>
<tr><th>Check</th><th>Result</th></tr>
<tr><td>Hard-coded secrets (working tree)</td><td>$AUD_SECRETS</td></tr>
<tr><td>Secrets in git history</td><td>$AUD_HIST_N</td></tr>
<tr><td>Sensitive files</td><td>$AUD_RISKY_N</td></tr>
<tr><td>Vulnerable dependencies</td><td>$AUD_VULN_N</td></tr>
<tr><td>CI / Docker / IaC findings</td><td>$AUD_EXTRA_N (high $AUD_EXTRA_HIGH, medium $AUD_EXTRA_MED, low $AUD_EXTRA_LOW)</td></tr>
<tr><td>Missing hygiene files</td><td>$AUD_HYG_MISS of 5</td></tr>
<tr><td>License</td><td>$(printf '%s' "$AUD_LICENSE" | html_esc)</td></tr>
</table>
<h2>Full report</h2>
<pre>$(render_md | html_esc)</pre>
</main></body></html>
EOF
}

write_reports() {
    local ts base fmt
    ts=$(date +%Y%m%d-%H%M%S); mkdir -p "$REPORT_DIR" || return 1
    base="$REPORT_DIR/${AUD_NAME}-${ts}"
    render_md > "$base.md"; LAST_REPORT="$base.md"
    for fmt in $(printf '%s' "$EXPORT_FMTS" | tr ',' ' '); do
        case "$fmt" in
            html) render_html > "$base.html"; log_info "HTML report: $base.html" ;;
            json) render_json > "$base.json"; log_info "JSON report: $base.json" ;;
            md)   ;;
            *)    log_warn "Unknown export format: $fmt (use html,json,md)" ;;
        esac
    done
}

action_audit() {
    local dir="${1:-.}"
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found: ${1:-.}"; return 1; }
    log_info "Auditing $dir ($([ "$AUDIT_FULL" = true ] && echo full || echo quick) mode)..."
    collect_audit "$dir"
    write_reports || return 1
    cat "$LAST_REPORT"; echo
    log_success "Grade $AUD_GRADE ($AUD_SCORE/100). Report: $LAST_REPORT"
    [ "$SAVE_BASELINE" = true ] && save_baseline
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$LAST_REPORT" >> "$GITHUB_STEP_SUMMARY"
    [ "$NOTIFY" = true ] && notify_send "$(audit_summary_line)"
    if [ "$AUD_SECRETS" -gt 0 ] || [ "$AUD_HIST_N" -gt 0 ]; then return 2; fi
    return 0
}

# ---- audit only what changed ---------------------------------------------------
default_base_ref() {
    local c base head
    head=$(git rev-parse HEAD 2>/dev/null)
    for c in origin/HEAD origin/main origin/master main master; do
        if git rev-parse --verify -q "$c" >/dev/null 2>&1; then
            base=$(git merge-base "$c" HEAD 2>/dev/null)
            [ -n "$base" ] && [ "$base" != "$head" ] && { echo "$base"; return; }
        fi
    done
    git rev-parse --verify -q HEAD~1 2>/dev/null || echo "4b825dc642cb6eb9a060e54bf8d69288fbee4904"  # empty tree
}

action_audit_diff() {
    in_git_repo || { log_error "Not a git repository."; return 1; }
    local ref="${1:-$(default_base_ref)}" hits u count files
    log_info "Auditing changes since $ref ..."
    files=$(git diff --name-only "$ref" 2>/dev/null | wc -l | tr -d ' ')
    git diff --stat "$ref" 2>/dev/null | tail -n 1
    hits=$(git diff -U0 --no-color "$ref" 2>/dev/null | scan_diff_added changed)
    while IFS= read -r u; do   # untracked files are not in `git diff`
        [ -f "$u" ] || continue
        grep -IEio -e "$SECRET_REGEX" "$u" 2>/dev/null | head -1 | awk -v f="$u" '{printf "untracked:%s  %s...[redacted]\n", f, substr($0,1,6)}'
    done < <(git ls-files --others --exclude-standard 2>/dev/null) > /tmp/.repodir_untracked.$$
    hits="$hits"$'\n'"$(cat /tmp/.repodir_untracked.$$)"; rm -f /tmp/.repodir_untracked.$$
    hits=$(printf '%s\n' "$hits" | grep -v '^$' | sort -u); count=$(count_lines "$hits"); SECRET_HITS=$count
    echo "Changed files: $files"
    if [ "$count" -gt 0 ]; then
        log_warn "$count potential secret(s) in the changes:"; printf '%s\n' "$hits" | head -n 50
        return 2
    fi
    log_success "No secrets in changed lines."
}

action_ai_review() {
    in_git_repo || { log_error "Not a git repository."; return 1; }
    action_install_opencode || return 1
    local ref="${1:-$(default_base_ref)}" diff
    diff=$(git diff --no-color "$ref" 2>/dev/null | head -c 60000)
    [ -n "$diff" ] || { log_warn "No changes to review since $ref."; return 0; }
    log_info "OpenCode is reviewing the diff since $ref (read-only)..."
    oc_run "You are a meticulous code reviewer. READ-ONLY: do not modify files. Review the following diff for bugs, security issues, missing error handling, broken edge cases and missing tests. Reply with a prioritized list (severity, file:line, issue, suggested fix) and a short verdict. DIFF:
$diff"
}

# ---- notifications ---------------------------------------------------------------
notify_send() {
    local text="$1" tmp sent=false
    [ -n "$SLACK_WEBHOOK$DISCORD_WEBHOOK$TG_TOKEN" ] || { log_warn "No notification channel configured (config SLACK_WEBHOOK=..., DISCORD_WEBHOOK=..., TG_TOKEN=... TG_CHAT=...)."; return 1; }
    need curl || return 1
    tmp=$(mktemp) || return 1
    if [ -n "$SLACK_WEBHOOK" ]; then
        printf '{"text":"%s"}' "$(json_esc "$text")" > "$tmp"
        printf 'url = "%s"\n' "$SLACK_WEBHOOK" | curl -fsS -m 10 -K - -X POST -H 'Content-Type: application/json' --data @"$tmp" >/dev/null 2>&1 && { sent=true; log_info "Slack notified."; } || log_warn "Slack notification failed."
    fi
    if [ -n "$DISCORD_WEBHOOK" ]; then
        printf '{"content":"%s"}' "$(json_esc "$text")" > "$tmp"
        printf 'url = "%s"\n' "$DISCORD_WEBHOOK" | curl -fsS -m 10 -K - -X POST -H 'Content-Type: application/json' --data @"$tmp" >/dev/null 2>&1 && { sent=true; log_info "Discord notified."; } || log_warn "Discord notification failed."
    fi
    if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
        printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TG_TOKEN" | curl -fsS -m 10 -K - --data-urlencode "chat_id=$TG_CHAT" --data-urlencode "text=$text" >/dev/null 2>&1 && { sent=true; log_info "Telegram notified."; } || log_warn "Telegram notification failed."
    fi
    rm -f "$tmp"
    [ "$sent" = true ]
}

action_notify_config() {
    local v
    echo "Leave blank to keep the current value."
    ask v "Slack webhook URL: " silent && [ -n "$v" ] && SLACK_WEBHOOK="$v"
    ask v "Discord webhook URL: " silent && [ -n "$v" ] && DISCORD_WEBHOOK="$v"
    ask v "Telegram bot token: " silent && [ -n "$v" ] && TG_TOKEN="$v"
    ask v "Telegram chat id: " && [ -n "$v" ] && TG_CHAT="$v"
    save_config && log_success "Notification settings saved."
}

# ---- multi-repo mode -----------------------------------------------------------------
action_repo_add() {
    local r="${1:-$TARGET_REPO}"
    [ -n "$r" ] || { log_error "Usage: repo-add owner/repo"; return 1; }
    mkdir -p "$DATA_DIR"; touch "$REPOS_FILE"
    if grep -qxF "$r" "$REPOS_FILE"; then log_info "Already saved: $r"; else echo "$r" >> "$REPOS_FILE"; log_success "Saved: $r"; fi
}
action_repo_rm() {
    local r="${1:-}" tmp
    [ -n "$r" ] && [ -f "$REPOS_FILE" ] || { log_error "Usage: repo-rm owner/repo"; return 1; }
    tmp=$(mktemp); grep -vxF "$r" "$REPOS_FILE" > "$tmp"; cat "$tmp" > "$REPOS_FILE"; rm -f "$tmp"; log_success "Removed: $r"
}
action_repo_list() {
    if [ -s "$REPOS_FILE" ]; then nl -ba "$REPOS_FILE"; else echo "No saved repos. Add one: repodir --repo-add owner/repo"; fi
}
action_repo_pick() {
    [ -s "$REPOS_FILE" ] || { log_error "No saved repos."; return 1; }
    local r; r=$(pick_from "Saved repo" < "$REPOS_FILE") || return 1
    TARGET_REPO="$r"; save_config; action_clone "$r"
}
action_pull_all() {
    local r; [ -s "$REPOS_FILE" ] || { log_error "No saved repos."; return 1; }
    while IFS= read -r r; do [ -n "$r" ] && ( action_clone "$r" >/dev/null 2>&1 && echo "  [ok]   $r" || echo "  [fail] $r" ); done < "$REPOS_FILE"
}
action_audit_all() {
    [ -s "$REPOS_FILE" ] || { log_error "No saved repos. Use: repodir --repo-add owner/repo"; return 1; }
    local r tmp worst=0; tmp=$(mktemp)
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        log_info "Auditing $r ..."
        (   action_clone "$r" >/dev/null 2>&1 || { printf '0\t%s\t-\t-\t-\t-\tclone failed\n' "$r" >> "$tmp"; exit 3; }
            collect_audit "$PWD"; write_reports
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$AUD_SCORE" "$r" "$AUD_GRADE" "$AUD_SECRETS" "$AUD_HIST_N" "$AUD_VULN_N" "$AUD_EXTRA_N" >> "$tmp" )
    done < "$REPOS_FILE"
    echo
    printf '%-6s %-40s %-6s %-8s %-8s %-6s %s\n' SCORE REPO GRADE SECRETS HISTORY VULNS CI/IAC
    sort -n "$tmp" | awk -F'\t' '{printf "%-6s %-40s %-6s %-8s %-8s %-6s %s\n",$1,$2,$3,$4,$5,$6,$7}'
    [ "$NOTIFY" = true ] && notify_send "repodir audit-all: $(sort -n "$tmp" | awk -F'\t' '{printf "%s=%s ",$2,$3}')"
    awk -F'\t' '$4>0||$5>0{f=1} END{exit f?2:0}' "$tmp"; worst=$?
    rm -f "$tmp"; return $worst
}

action_gh_list() {
    local list pick
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        list=$(gh repo list --limit 100 --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null)
    elif [ -n "$GPH_KEY" ]; then
        list=$(gh_api "/user/repos?per_page=100&sort=pushed" | grep -o '"full_name": *"[^"]*"' | sed 's/.*: *"//; s/"$//' | sort -u)
    else
        log_error "Need the GitHub CLI (gh auth login) or a token (config GPH_KEY=...)."; return 1
    fi
    [ -n "$list" ] || { log_error "Could not list repositories."; return 1; }
    if [ "$INTERACTIVE" != true ]; then printf '%s\n' "$list"; return 0; fi
    pick=$(printf '%s\n' "$list" | pick_from "GitHub repo") || return 1
    TARGET_REPO="$pick"; save_config; log_success "Target: $pick"
    confirm "Clone / pull it now?" y && action_clone "$pick"
    confirm "Save it to your multi-repo list?" n && action_repo_add "$pick"
    return 0
}

# ==============================================================================
# BUILD SYSTEM: detect project type -> suggest builds -> build -> collect to ./dist
# ==============================================================================
pkg_has()    { [ -f package.json ] && grep -qE "\"$1\"[[:space:]]*:" package.json; }
pkg_script() { [ -f package.json ] && grep -qE "\"$1\"[[:space:]]*:" package.json; }
proj_name()  { basename "$PWD" | sed 's/[^A-Za-z0-9._-]/_/g'; }

android_sdk_dir() {
    local d
    for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/android-sdk" "/usr/lib/android-sdk"; do
        [ -n "$d" ] && [ -d "$d" ] && { printf '%s' "$d"; return 0; }
    done
    if [ -f local.properties ] && grep -q '^sdk.dir' local.properties 2>/dev/null; then printf '%s' "local.properties"; return 0; fi
    if [ -f android/local.properties ] && grep -q '^sdk.dir' android/local.properties 2>/dev/null; then printf '%s' "android/local.properties"; return 0; fi
    return 1
}

# Which project types live in this directory? (one id per line)
detect_types() {
    local d="${1:-.}" cs
    ( cd "$d" 2>/dev/null || exit 0
      if [ -f pubspec.yaml ] && grep -qE '^[[:space:]]*flutter:' pubspec.yaml; then echo flutter; fi
      if [ -f package.json ]; then
          if pkg_has react-native; then
              if pkg_has expo; then echo expo; else echo rn; fi
          elif pkg_has '@capacitor/core'; then echo capacitor
          fi
          if [ -d src-tauri ] || pkg_has '@tauri-apps/api' || pkg_has '@tauri-apps/cli'; then echo tauri; fi
          if pkg_has electron; then echo electron; fi
          if ! pkg_has react-native && ! pkg_has electron && [ ! -d src-tauri ]; then
              if pkg_script build && { pkg_has vite || pkg_has next || pkg_has react-scripts || pkg_has nuxt || pkg_has vue || pkg_has svelte || pkg_has astro || pkg_has '@angular/core' || pkg_has webpack; }; then echo web
              elif pkg_has bin || pkg_has main; then echo node-cli; fi
          fi
      fi
      if [ -f gradlew ] || [ -f build.gradle ] || [ -f build.gradle.kts ] || [ -f settings.gradle ] || [ -f settings.gradle.kts ]; then
          if [ -f app/src/main/AndroidManifest.xml ] || [ -f src/main/AndroidManifest.xml ] || grep -rqsE 'com\.android\.(application|library)' --include='build.gradle' --include='build.gradle.kts' . 2>/dev/null; then echo android; else echo gradle; fi
      fi
      [ -f go.mod ] && echo go
      [ -f Cargo.toml ] && echo rust
      [ -f pom.xml ] && echo maven
      if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || [ -f requirements.txt ] || [ -f main.py ] || [ -f app.py ]; then echo python; fi
      cs=$(find . -maxdepth 2 \( -name '*.csproj' -o -name '*.fsproj' -o -name '*.sln' \) 2>/dev/null | head -1)
      [ -n "$cs" ] && echo dotnet
      [ -f build.zig ] && echo zig
      [ -f CMakeLists.txt ] && echo cmake
      if [ -f Makefile ] || [ -f makefile ]; then [ -f CMakeLists.txt ] || echo make; fi
      [ -f Dockerfile ] && echo docker
      exit 0 )
}

type_desc() {
    case "$1" in
        android) echo "Native Android app (Gradle)";;  flutter) echo "Flutter app";;
        rn) echo "React Native app";;                  expo) echo "Expo / React Native app";;
        capacitor) echo "Capacitor hybrid app";;       tauri) echo "Tauri desktop app";;
        electron) echo "Electron desktop app";;        web) echo "Web frontend (npm build)";;
        node-cli) echo "Node.js CLI / library";;       go) echo "Go module";;
        rust) echo "Rust crate";;                      python) echo "Python project";;
        dotnet) echo ".NET solution/project";;        maven) echo "Java (Maven)";;
        gradle) echo "JVM project (Gradle)";;          cmake) echo "C/C++ (CMake)";;
        make) echo "Makefile project";;                zig) echo "Zig project";;
        docker) echo "Docker image";;                  *) echo "$1";;
    esac
}

# build_targets TYPE -> "id|label|requirements,comma,separated" per line (first = recommended)
build_targets() {
    case "$1" in
        android)   cat <<'EOF'
debug|APK - debug (signed with debug key, installable right away)|java,gradle,android-sdk
release|APK - release (unsigned unless a signing config exists)|java,gradle,android-sdk
aab|Android App Bundle .aab (Google Play)|java,gradle,android-sdk
EOF
;;
        flutter)   cat <<'EOF'
apk|Android APK (release)|flutter,java,android-sdk
apk-split|Android APKs split per ABI (smaller)|flutter,java,android-sdk
aab|Android App Bundle .aab (Google Play)|flutter,java,android-sdk
linux|Linux desktop bundle|flutter,linux-host
windows|Windows desktop bundle|flutter,windows-host
web|Web build|flutter
EOF
;;
        rn)        cat <<'EOF'
apk|Android APK - release (Gradle)|node,npm,java,android-sdk
debug|Android APK - debug|node,npm,java,android-sdk
EOF
;;
        expo)      cat <<'EOF'
apk-local|Android APK (expo prebuild + Gradle)|node,npm,java,android-sdk
eas-local|Android APK via EAS local build (preview profile)|node,npm,java,android-sdk
EOF
;;
        capacitor) cat <<'EOF'
apk|Android debug APK (build web, cap sync, Gradle)|node,npm,java,android-sdk
EOF
;;
        tauri)     cat <<'EOF'
bundle|Native installers for THIS OS (deb/AppImage/msi/dmg)|node,npm,cargo
EOF
;;
        electron)  cat <<'EOF'
both|Linux + Windows installers (electron-builder)|node,npm
linux|Linux (AppImage/deb)|node,npm
win|Windows installer (on Linux this needs wine)|node,npm
EOF
;;
        node-cli)  cat <<'EOF'
pkg|Standalone binaries: Linux + Windows + macOS (pkg)|node,npm
bun|Standalone binaries: Linux + Windows (bun compile)|bun
pack|npm tarball (npm pack)|npm
EOF
;;
        web)       cat <<'EOF'
build|Production web build (npm run build)|node,npm
EOF
;;
        go)        cat <<'EOF'
lw|Linux + Windows binaries (amd64)|go
cross|Linux / Windows / macOS x amd64 + arm64|go
native|Native binary for this machine|go
EOF
;;
        rust)      cat <<'EOF'
native|Native release binary|cargo
win-gnu|Windows .exe from Linux (mingw, x86_64-pc-windows-gnu)|cargo,rustup,mingw
cross|Linux (musl) + Windows via 'cross' (needs Docker)|cargo,cross,docker
zig|Linux + Windows via cargo-zigbuild|cargo,cargo-zigbuild,zig
EOF
;;
        python)    cat <<'EOF'
exe|Single-file executable for THIS OS (PyInstaller)|python3
wheel|Wheel + sdist (python -m build)|python3
EOF
;;
        dotnet)    cat <<'EOF'
single|Self-contained single-file: linux-x64 + win-x64|dotnet
all|Linux / Windows / macOS x x64 + arm64|dotnet
EOF
;;
        maven)     echo 'jar|Package JAR (mvn package)|java,mvn';;
        gradle)    echo 'jar|Gradle build (skip tests)|java,gradle';;
        cmake)     cat <<'EOF'
native|Native Release build (CMake)|cmake
win-mingw|Windows .exe via MinGW|cmake,mingw
EOF
;;
        make)      echo 'native|make|make';;
        zig)       cat <<'EOF'
cross|Linux + Windows + macOS (zig cross-compile)|zig
native|Native (ReleaseSafe)|zig
EOF
;;
        docker)    echo 'image|Docker image (docker build)|docker';;
    esac
}

req_ok() {
    case "$1" in
        gradle)       [ -f ./gradlew ] || [ -f ./android/gradlew ] || command -v gradle >/dev/null 2>&1 ;;
        android-sdk)  android_sdk_dir >/dev/null ;;
        mingw)        command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 ;;
        windows-host) [ "$OS_NAME" = windows ] ;;
        linux-host)   [ "$OS_NAME" = linux ] || [ "$OS_NAME" = wsl ] ;;
        cargo-zigbuild) command -v cargo-zigbuild >/dev/null 2>&1 ;;
        *)            command -v "$1" >/dev/null 2>&1 ;;
    esac
}

req_hint() {
    case "$1" in
        java)        echo "Install JDK 17:  apt install openjdk-17-jdk | brew install openjdk@17 | winget install EclipseAdoptium.Temurin.17.JDK";;
        gradle)      echo "Add the Gradle wrapper (gradlew) or install Gradle: https://gradle.org/install";;
        android-sdk) echo "Install Android command-line tools, set ANDROID_HOME, then: sdkmanager \"platforms;android-34\" \"build-tools;34.0.0\"  (https://developer.android.com/studio#command-line-tools-only)";;
        flutter)     echo "Install Flutter: https://docs.flutter.dev/get-started/install";;
        node|npm)    echo "Install Node.js LTS: https://nodejs.org (or nvm / fnm)";;
        bun)         echo "Install bun: curl -fsSL https://bun.sh/install | bash";;
        go)          echo "Install Go: https://go.dev/dl";;
        cargo|rustup) echo "Install Rust: curl https://sh.rustup.rs -sSf | sh";;
        mingw)       echo "Install MinGW-w64:  apt install mingw-w64 | brew install mingw-w64";;
        cross)       echo "Install cross:  cargo install cross --git https://github.com/cross-rs/cross";;
        cargo-zigbuild) echo "Install: cargo install cargo-zigbuild  (and zig)";;
        zig)         echo "Install Zig: https://ziglang.org/download";;
        docker)      echo "Install Docker: https://docs.docker.com/get-docker";;
        python3)     echo "Install Python 3.8+: https://python.org";;
        dotnet)      echo "Install .NET SDK: https://dotnet.microsoft.com/download";;
        mvn)         echo "Install Maven: https://maven.apache.org/install.html";;
        cmake)       echo "Install CMake: apt install cmake | brew install cmake";;
        make)        echo "Install make (build-essential / Xcode CLT)";;
        windows-host) echo "This target can only be built on a Windows host (use CI: windows-latest runner)";;
        linux-host)  echo "This target can only be built on a Linux host";;
        *)           echo "Install: $1";;
    esac
}

missing_reqs() {  # missing_reqs "a,b,c" -> prints missing tokens (one per line)
    local r
    for r in $(printf '%s' "$1" | tr ',' ' '); do req_ok "$r" || echo "$r"; done
}

action_detect() {
    local dir="${1:-.}" types t line id label reqs miss tag
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found."; return 1; }
    types=$(detect_types "$dir")
    if [ -z "$types" ]; then log_warn "No recognised project type in $dir."; return 1; fi
    echo "Project: $dir"
    for t in $types; do
        echo
        echo "Detected: $t - $(type_desc "$t")"
        while IFS='|' read -r id label reqs; do
            [ -n "$id" ] || continue
            miss=$( cd "$dir" && missing_reqs "$reqs" | tr '\n' ' ')
            if [ -z "$miss" ]; then tag="[ready]"; else tag="[needs: ${miss% }]"; fi
            printf '   %-12s %-62s %s\n' "$t:$id" "$label" "$tag"
        done <<< "$(build_targets "$t")"
    done
    echo
    echo "Build one:  repodir --build <type>:<target>     e.g. repodir --build $(printf '%s\n' "$types" | head -1):$(build_targets "$(printf '%s\n' "$types" | head -1)" | head -1 | cut -d'|' -f1)"
}

# ---- helpers used by builders ---------------------------------------------------
gradle_cmd() { if [ -f ./gradlew ]; then chmod +x ./gradlew 2>/dev/null; echo ./gradlew; else echo gradle; fi; }
android_env() { local s; s=$(android_sdk_dir) && [ -d "$s" ] && { export ANDROID_HOME="${ANDROID_HOME:-$s}"; export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"; }; return 0; }

node_install() {
    [ -d node_modules ] && return 0
    if   [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then pnpm install
    elif [ -f yarn.lock ]      && command -v yarn >/dev/null 2>&1; then yarn install
    elif [ -f package-lock.json ]; then npm ci || npm install
    else npm install; fi
}
pm_run() {
    if   [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then pnpm run "$@"
    elif [ -f yarn.lock ]      && command -v yarn >/dev/null 2>&1; then yarn run "$@"
    else npm run "$@"; fi
}

py_env() {  # py_env pkgs... -> PYBIN (isolated venv; never touches system python)
    local v="$DATA_DIR/venv-build"
    [ -d "$v" ] || python3 -m venv "$v" || return 1
    if [ -d "$v/Scripts" ]; then PYBIN="$v/Scripts"; else PYBIN="$v/bin"; fi
    "$PYBIN/python" -m pip install -q --upgrade pip "$@" || return 1
    if [ -f requirements.txt ]; then "$PYBIN/python" -m pip install -q -r requirements.txt || log_warn "Some requirements failed to install; build may fail."; fi
}
py_entry() {
    local n c; n=$(proj_name)
    for c in main.py app.py cli.py run.py __main__.py "src/main.py" "$n/__main__.py" "$n/main.py" "src/$n/__main__.py"; do
        [ -f "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}
cargo_name() { sed -n 's/^name *= *"\(.*\)"/\1/p' Cargo.toml | head -1; }

build_go() {
    local mode="$1" pkgs p name matrix t os arch ext fail=0
    pkgs=$(go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... 2>/dev/null | grep .)
    [ -n "$pkgs" ] || { log_error "No 'package main' found in this module."; return 1; }
    case "$mode" in
        native) matrix="$(go env GOOS)/$(go env GOARCH)" ;;
        lw)     matrix="linux/amd64 windows/amd64" ;;
        cross)  matrix="linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/amd64 darwin/arm64" ;;
    esac
    mkdir -p dist
    for p in $pkgs; do
        name="${p##*/}"; [[ "$name" =~ ^v[0-9]+$ ]] && name=$(proj_name)
        for t in $matrix; do
            os="${t%/*}"; arch="${t#*/}"; ext=""; [ "$os" = windows ] && ext=".exe"
            log_info "go build $os/$arch -> dist/${name}-${os}-${arch}${ext}"
            CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "dist/${name}-${os}-${arch}${ext}" "$p" || fail=1
        done
    done
    return $fail
}

build_dotnet() {
    local rids="$1" rid fail=0
    for rid in $rids; do
        log_info "dotnet publish $rid"
        dotnet publish -c Release -r "$rid" --self-contained true -p:PublishSingleFile=true -o "dist/$rid" || fail=1
    done
    return $fail
}

build_zig() {
    local mode="$1" t fail=0 targets
    if [ "$mode" = cross ]; then targets="x86_64-linux x86_64-windows x86_64-macos aarch64-macos aarch64-linux"; else targets=""; fi
    if [ -z "$targets" ]; then zig build -Doptimize=ReleaseSafe -p dist/native; return $?; fi
    for t in $targets; do log_info "zig build -Dtarget=$t"; zig build -Doptimize=ReleaseSafe -Dtarget="$t" -p "dist/$t" || fail=1; done
    return $fail
}

# do_build TYPE TARGET   (runs inside a pipeline subshell; must not prompt)
do_build() {
    local type="$1" target="$2" n entry gc
    n=$(proj_name)
    case "$type" in
        android|rn|expo|capacitor|flutter) android_env ;;
    esac
    case "$type:$target" in
        android:debug)   $(gradle_cmd) assembleDebug ;;
        android:release) $(gradle_cmd) assembleRelease ;;
        android:aab)     $(gradle_cmd) bundleRelease ;;

        flutter:apk)       flutter pub get && flutter build apk --release ;;
        flutter:apk-split) flutter pub get && flutter build apk --release --split-per-abi ;;
        flutter:aab)       flutter pub get && flutter build appbundle --release ;;
        flutter:linux)     flutter pub get && flutter build linux --release && mkdir -p dist &&
                           tar czf "dist/${n}-linux-$ARCH.tar.gz" -C "$(ls -d build/linux/*/release/bundle | head -1)" . ;;
        flutter:windows)   flutter pub get && flutter build windows --release && mkdir -p dist &&
                           ( cd "$(ls -d build/windows/*/runner/Release | head -1)" && zip -qr "$OLDPWD/dist/${n}-windows.zip" . ) ;;
        flutter:web)       flutter pub get && flutter build web --release ;;

        rn:apk)    node_install && ( cd android && chmod +x gradlew 2>/dev/null; ./gradlew assembleRelease ) ;;
        rn:debug)  node_install && ( cd android && chmod +x gradlew 2>/dev/null; ./gradlew assembleDebug ) ;;
        expo:apk-local) node_install && npx --yes expo prebuild --platform android --no-install &&
                        ( cd android && chmod +x gradlew 2>/dev/null; ./gradlew assembleRelease ) ;;
        expo:eas-local) node_install && npx --yes eas-cli build --platform android --profile preview --local --non-interactive ;;
        capacitor:apk)  node_install && { pkg_script build && pm_run build || true; } && npx --yes cap sync android &&
                        ( cd android && chmod +x gradlew 2>/dev/null; ./gradlew assembleDebug ) ;;

        tauri:bundle)   node_install && { pm_run tauri build || cargo tauri build; } ;;

        electron:linux|electron:win|electron:both)
            node_install || return 1
            if pkg_script build; then pm_run build || return 1; fi
            case "$target" in linux) npx --yes electron-builder --linux ;; win) npx --yes electron-builder --win ;; both) npx --yes electron-builder --linux --win ;; esac ;;

        node-cli:pkg)  node_install && npx --yes @yao-pkg/pkg . --targets node20-linux-x64,node20-win-x64,node20-macos-x64 --out-path dist ;;
        node-cli:bun)
            node_install; entry=$(sed -n 's/.*"main"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -1)
            for gc in "$entry" src/index.ts src/index.js index.ts index.js; do [ -n "$gc" ] && [ -f "$gc" ] && { entry="$gc"; break; }; done
            [ -f "$entry" ] || { log_error "Cannot find an entry file for bun."; return 1; }
            mkdir -p dist
            bun build --compile --target=bun-linux-x64   "$entry" --outfile "dist/${n}-linux-x64" &&
            bun build --compile --target=bun-windows-x64 "$entry" --outfile "dist/${n}-windows-x64.exe" ;;
        node-cli:pack) mkdir -p dist && npm pack --pack-destination dist ;;
        web:build)     node_install && pm_run build ;;

        go:native) build_go native ;;
        go:lw)     build_go lw ;;
        go:cross)  build_go cross ;;

        rust:native)  cargo build --release ;;
        rust:win-gnu) rustup target add x86_64-pc-windows-gnu && cargo build --release --target x86_64-pc-windows-gnu ;;
        rust:cross)   cross build --release --target x86_64-unknown-linux-musl && cross build --release --target x86_64-pc-windows-gnu ;;
        rust:zig)     rustup target add x86_64-unknown-linux-gnu x86_64-pc-windows-gnu 2>/dev/null
                      cargo zigbuild --release --target x86_64-unknown-linux-gnu && cargo zigbuild --release --target x86_64-pc-windows-gnu ;;

        python:exe)
            entry=$(py_entry) || { log_error "No entry script found (main.py/app.py/cli.py...)."; return 1; }
            py_env pyinstaller || return 1
            "$PYBIN/pyinstaller" --noconfirm --onefile --name "$n" --distpath dist --workpath "$DATA_DIR/pybuild" --specpath "$DATA_DIR/pybuild" "$PWD/$entry" ;;
        python:wheel)  py_env build || return 1; "$PYBIN/python" -m build --outdir dist ;;

        dotnet:single) build_dotnet "linux-x64 win-x64" ;;
        dotnet:all)    build_dotnet "linux-x64 linux-arm64 win-x64 win-arm64 osx-x64 osx-arm64" ;;

        maven:jar)   mvn -B -q package -DskipTests ;;
        gradle:jar)  $(gradle_cmd) build -x test ;;

        cmake:native)
            cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -j ;;
        cmake:win-mingw)
            cmake -S . -B build-win -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Windows \
                  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ &&
            cmake --build build-win -j ;;
        make:native) make ;;

        zig:cross)  build_zig cross ;;
        zig:native) build_zig native ;;

        docker:image) docker build -t "$(printf '%s' "$n" | tr 'A-Z' 'a-z'):latest" . ;;

        *) log_error "No builder for $type:$target"; return 1 ;;
    esac
}

collect_artifacts() {  # collect_artifacts TYPE MARKER  -> copies outputs into ./dist
    local type="$1" marker="$2" f base triple n
    n=$(proj_name); mkdir -p dist
    case "$type" in
        android|rn|expo|capacitor|flutter)
            find . \( -path ./node_modules -o -path ./.git -o -path ./dist \) -prune -o -type f \( -name '*.apk' -o -name '*.aab' \) -newer "$marker" -print 2>/dev/null |
            while IFS= read -r f; do cp -f "$f" "dist/$(basename "$f")"; done ;;
        tauri)
            find src-tauri/target -path '*/bundle/*' -type f \( -name '*.deb' -o -name '*.AppImage' -o -name '*.rpm' -o -name '*.msi' -o -name '*.exe' -o -name '*.dmg' \) -newer "$marker" 2>/dev/null |
            while IFS= read -r f; do cp -f "$f" "dist/$(basename "$f")"; done ;;
        rust)
            for d in target/release target/*/release; do
                [ -d "$d" ] || continue
                triple=$(printf '%s' "$d" | sed -n 's|^target/\(.*\)/release$|\1|p'); [ -n "$triple" ] || triple="$OS_NAME-$ARCH"
                find "$d" -maxdepth 1 -type f \( -perm -u+x -o -name '*.exe' \) ! -name '*.d' ! -name '*.so' ! -name '*.dylib' ! -name '*.rlib' ! -name '*.pdb' -newer "$marker" 2>/dev/null |
                while IFS= read -r f; do
                    base=$(basename "$f")
                    case "$base" in *.exe) cp -f "$f" "dist/${base%.exe}-$triple.exe" ;; *) cp -f "$f" "dist/$base-$triple" ;; esac
                done
            done ;;
        maven)  find target -maxdepth 1 -name '*.jar' -newer "$marker" ! -name 'original-*' -exec cp -f {} dist/ \; 2>/dev/null ;;
        gradle) find build/libs -maxdepth 1 -name '*.jar' -newer "$marker" -exec cp -f {} dist/ \; 2>/dev/null ;;
        cmake|make)
            find build build-win . -maxdepth 2 -type f \( -perm -u+x -o -name '*.exe' \) -newer "$marker" ! -path './dist/*' ! -path '*/CMakeFiles/*' ! -name '*.sh' ! -name '*.so*' ! -name '*.a' ! -name '*.cmake' 2>/dev/null |
            while IFS= read -r f; do cp -f "$f" "dist/$(basename "$f")"; done ;;
    esac
    return 0
}

write_checksums() {
    [ -d dist ] || return 0
    local f; : > dist/SHA256SUMS
    find dist -maxdepth 1 -type f ! -name SHA256SUMS | sort | while IFS= read -r f; do
        printf '%s  %s\n' "$(sha256_of "$f")" "$(basename "$f")" >> dist/SHA256SUMS
    done
}

action_build() {
    local t spec="${1:-}" want_type="" want_target="" types type targets target line reqs miss log marker rc sel
    [ -n "$spec" ] && { want_type="${spec%%:*}"; [ "$spec" != "$want_type" ] && want_target="${spec#*:}"; }
    types=$(detect_types .)
    [ -n "$types" ] || { log_error "No recognised project type in $(pwd). Try: repodir --from <path|repo> --detect"; return 1; }

    if [ -n "$want_type" ]; then
        grep -qx "$want_type" <<< "$types" || { log_error "Type '$want_type' not detected here. Detected: $(printf '%s ' $types)"; return 1; }
        type="$want_type"
    else
        sel=$(for t in $types; do printf '%s - %s\n' "$t" "$(type_desc "$t")"; done | pick_from "Project type") || return 1
        type="${sel%% - *}"
    fi

    targets=$(build_targets "$type")
    if [ -n "$want_target" ]; then
        line=$(grep "^$want_target|" <<< "$targets")
        [ -n "$line" ] || { log_error "Unknown target '$want_target' for $type. Options: $(printf '%s\n' "$targets" | cut -d'|' -f1 | tr '\n' ' ')"; return 1; }
        target="$want_target"
    else
        sel=$(printf '%s\n' "$targets" | awk -F'|' '{printf "%s (%s)\n",$2,$1}' | pick_from "Build target") || return 1
        target="${sel##*(}"; target="${target%)}"
    fi
    reqs=$(grep "^$target|" <<< "$targets" | cut -d'|' -f3)

    miss=$(missing_reqs "$reqs")
    if [ -n "$miss" ]; then
        log_error "Missing requirements for $type:$target:"
        while IFS= read -r line; do [ -n "$line" ] && echo "  - $line: $(req_hint "$line")"; done <<< "$miss"
        return 1
    fi

    mkdir -p "$BUILD_LOG_DIR"; log="$BUILD_LOG_DIR/$(proj_name)-$type-$target-$(date +%Y%m%d-%H%M%S).log"
    marker=$(mktemp) || return 1; sleep 1
    log_info "Building $type:$target in $(pwd)  (log: $log)"
    { do_build "$type" "$target"; } 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    cp -f "$log" "$BUILD_LOG_DIR/last.log" 2>/dev/null

    if [ "$rc" -ne 0 ]; then
        rm -f "$marker"
        log_error "Build failed (exit $rc). Log: $log"
        if [ "$INTERACTIVE" = true ] && confirm "Ask OpenCode to diagnose and fix the build?" n; then
            action_ai_build_fix "$log" "$spec"
        fi
        return "$rc"
    fi
    collect_artifacts "$type" "$marker"; rm -f "$marker"
    write_checksums
    if [ -d dist ] && [ -n "$(find dist -type f ! -name SHA256SUMS 2>/dev/null | head -1)" ]; then
        log_success "Build complete. Artifacts in $(pwd)/dist:"
        ( cd dist && find . -type f ! -name SHA256SUMS | sort | head -n 40 | while IFS= read -r f; do printf '   %s  (%s)\n' "${f#./}" "$(du -h "$f" | cut -f1)"; done )
        echo "   SHA256SUMS written."
    else
        log_success "Build complete (outputs are in the project's normal build folder)."
    fi
    case "$type:$target" in
        android:release|flutter:apk*|rn:apk|expo:apk-local) log_warn "Release APKs are only installable if signed. If it is unsigned, sign with: apksigner sign --ks <keystore> <apk>  (debug builds are already installable)." ;;
    esac
    return 0
}

action_release() {  # release <tag>  -> upload dist/* to a GitHub release
    local tag="${1:-}"
    ensure_arg tag "$tag" "Release tag (e.g. v1.0.0): " || { log_error "Tag required."; return 1; }
    need gh git || return 1
    [ -d dist ] && [ -n "$(find dist -type f 2>/dev/null | head -1)" ] || { log_error "Nothing in ./dist - run a build first."; return 1; }
    write_checksums
    confirm_or_yes "Create GitHub release $tag with $(find dist -type f | wc -l | tr -d ' ') file(s)?" y || return 1
    gh release create "$tag" dist/* --generate-notes
}

# ---- tests --------------------------------------------------------------------------
detect_test_cmd() {
    if   [ -f package.json ] && grep -qE '"test"[[:space:]]*:' package.json; then echo "CI=true npm test --silent"
    elif [ -f go.mod ]; then echo "go test ./..."
    elif [ -f Cargo.toml ]; then echo "cargo test"
    elif [ -f pom.xml ]; then echo "mvn -B -q test"
    elif [ -f gradlew ]; then echo "./gradlew test"
    elif ls ./*.sln ./*.csproj >/dev/null 2>&1; then echo "dotnet test"
    elif [ -f pytest.ini ] || [ -d tests ] || [ -f pyproject.toml ] || [ -f setup.py ]; then echo "python3 -m pytest -q"
    elif [ -f Makefile ] && grep -qE '^test:' Makefile; then echo "make test"
    fi
}

action_tests() {
    local c; c=$(detect_test_cmd)
    [ -n "$c" ] || { log_warn "No test command detected."; return 1; }
    log_info "Running: $c"
    bash -c "$c"
}

# ==============================================================================
# OPENCODE AI AUDIT + MAINTENANCE TASKS (always on a git branch: review/revert freely)
# ==============================================================================
action_ai_audit() {
    local dir="${1:-.}" name ts out rc prompt
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found."; return 1; }
    action_install_opencode || return 1
    name=$(basename "$dir"); ts=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$REPORT_DIR" || return 1
    out="$REPORT_DIR/${name}-ai-${ts}.md"
    prompt='You are a senior security and code-quality auditor. This is a READ-ONLY task: do NOT modify, create or delete any files. Audit this repository for: (1) security vulnerabilities and exposed secrets, (2) bugs and logic errors, (3) risky or outdated dependencies, (4) code quality and maintainability, (5) missing tests, CI and docs. Output a Markdown report with an executive summary, a findings table (severity, file:line, issue, recommended fix) and a prioritized action plan.'
    log_info "Running OpenCode AI audit (needs a provider: run 'opencode auth login' or export a provider API key)..."
    ( cd "$dir" && oc_run "$prompt" ) | tee "$out"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then log_error "OpenCode exited with code $rc."; return "$rc"; fi
    log_success "AI report saved: $out"
    [ "$NOTIFY" = true ] && notify_send "repodir AI audit finished for $name: $out"
    return 0
}

BR_ORIG=""; BR_NAME=""

# branch_begin slug : safety checks + create a working branch
branch_begin() {
    need git || return 1
    in_git_repo || { log_error "Not a git repository. AI/update tasks need git so every change can be reviewed or reverted."; return 1; }
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        log_error "Working tree has uncommitted changes. Commit or stash them first."; return 1
    fi
    BR_ORIG=$(git rev-parse --abbrev-ref HEAD)
    BR_NAME="repodir/$1-$(date +%Y%m%d-%H%M%S)"
    confirm_or_yes "Create branch '$BR_NAME' and let tools modify files there?" y || return 1
    git checkout -q -b "$BR_NAME" || return 1
    log_info "Working on branch $BR_NAME (original: $BR_ORIG)"
}

# branch_abort : drop an empty working branch
branch_abort() { git checkout -q "$BR_ORIG" 2>/dev/null; git branch -D -q "$BR_NAME" 2>/dev/null; }

# branch_finish "commit message" [run_tests=true]
branch_finish() {
    local msg="$1" tests="${2:-false}" tcmd id=()
    if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
        log_warn "No changes were made."; branch_abort; return 0
    fi
    echo; git status --short | head -n 30; git diff --stat | tail -n 1
    if [ "$tests" = true ]; then
        tcmd=$(detect_test_cmd)
        if [ -n "$tcmd" ] && confirm_or_yes "Run tests ($tcmd) before committing?" y; then
            bash -c "$tcmd" && log_success "Tests passed." || log_warn "Tests FAILED - review before merging."
        fi
    fi
    if confirm_or_yes "Commit these changes on $BR_NAME?" y; then
        [ -z "$(git config user.email)" ] && id=(-c user.name="repodir" -c user.email="repodir@localhost")
        git add -A && git ${id[@]+"${id[@]}"} commit -q -m "$msg" && log_success "Committed: $msg"
        if [ "$INTERACTIVE" = true ] && git remote get-url origin >/dev/null 2>&1 && confirm "Push branch and open a pull request (gh)?" n; then
            git_auth push -u origin "$BR_NAME" && { command -v gh >/dev/null 2>&1 && gh pr create --fill || log_info "Pushed. Open a PR on GitHub."; }
        fi
    else
        log_info "Changes left uncommitted on $BR_NAME."
    fi
    echo "Review: git diff $BR_ORIG..$BR_NAME    Merge: git checkout $BR_ORIG && git merge $BR_NAME    Discard: git checkout $BR_ORIG && git branch -D $BR_NAME"
}

# ai_task slug "commit message" "prompt" [tests]
ai_task() {
    local slug="$1" msg="$2" prompt="$3" tests="${4:-false}" rc
    action_install_opencode || return 1
    branch_begin "$slug" || return 1
    log_info "OpenCode is working (this can take a few minutes)..."
    oc_run "$prompt"; rc=$?
    [ "$rc" -ne 0 ] && log_warn "OpenCode exited with code $rc."
    branch_finish "$msg" "$tests"
}

action_ai_task() {
    local p="${1:-}"
    ensure_arg p "$p" "What should OpenCode do? " || { log_error "No task given."; return 1; }
    ai_task "task" "chore: $(printf '%s' "$p" | head -c 60)" "$p

Rules: make focused changes only, do not touch unrelated files, keep the project building, and finish with a short summary of what you changed." true
}

action_ai_update() {
    action_outdated
    ai_task "update" "chore(deps): update dependencies" "Update this project's dependencies to their latest stable, compatible versions. Detect the package manager(s) (npm/pnpm/yarn, pip/poetry/uv, go modules, cargo, maven/gradle, nuget, bundler, composer). Update manifests and lockfiles, then run the existing build and tests and fix any breakage caused by the upgrades (including deprecated API usage). Prefer minor/patch updates first; only take major bumps when you can fix the fallout. Do not modify unrelated code. Finish with a concise summary: old -> new versions, and anything you could not upgrade and why." true
}

action_deps_update() {  # tool-based (no AI): npm update / go get -u / cargo update
    branch_begin "deps" || return 1
    [ -f package.json ] && command -v npm >/dev/null 2>&1 && { log_info "npm update"; npm update; }
    [ -f go.mod ] && command -v go >/dev/null 2>&1 && { log_info "go get -u ./... && go mod tidy"; go get -u ./... && go mod tidy; }
    [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1 && { log_info "cargo update"; cargo update; }
    [ -f composer.json ] && command -v composer >/dev/null 2>&1 && { log_info "composer update"; composer update; }
    [ -f Gemfile ] && command -v bundle >/dev/null 2>&1 && { log_info "bundle update"; bundle update; }
    branch_finish "chore(deps): update dependencies" true
}

action_ai_fix() {
    local rep
    if [ -z "$LAST_REPORT" ] || [ ! -f "$LAST_REPORT" ]; then
        log_info "No audit yet - running one first..."
        collect_audit "$PWD"; write_reports
    fi
    rep=$(head -c 9000 "$LAST_REPORT")
    ai_task "audit-fix" "fix: address repodir audit findings" "Below is a security/quality audit report for this repository. Fix the issues you can fix safely: remove hard-coded secrets (move them to environment variables / config and add the file to .gitignore; NEVER print real secret values), pin or fix risky CI/Docker/IaC settings, add missing hygiene files (README, LICENSE choice should be left to the owner - only add a SECURITY.md and .gitignore entries), and patch vulnerable dependencies. Do not change behaviour unrelated to the findings. Finish with a summary of what you fixed and what needs a human (e.g. credentials that must be rotated).

AUDIT REPORT:
$rep" true
}

action_ai_preset() {
    case "$1" in
        ai-docs)      ai_task "docs" "docs: refresh documentation" "Review this repository and improve its documentation: create or update README.md (what it is, install, usage, configuration, examples, build/test instructions, license note) so it matches the actual code. Keep it accurate - read the code, do not invent features. Do not modify source code." ;;
        ai-tests)     ai_task "tests" "test: add tests for untested code" "Find the most important untested code paths in this repository and add focused, meaningful unit tests using the project's existing test framework (set one up with the idiomatic default if none exists). Do not change production code unless a tiny change is required for testability. Run the tests and make sure they pass." true ;;
        ai-changelog) ai_task "changelog" "docs: update CHANGELOG" "Create or update CHANGELOG.md in Keep a Changelog format using the git history since the latest tag (or the whole history if there are no tags). Group entries into Added/Changed/Fixed/Security, write them for users (not raw commit messages), and keep any existing entries. Do not modify other files." ;;
        ai-explain)   ai_task "explain" "docs: add ARCHITECTURE overview" "Read this repository and write ARCHITECTURE.md for new contributors: purpose, directory map, main components and how they interact, data flow, how to build/run/test, and key conventions. Be accurate and concise. Do not modify other files." ;;
    esac
}

action_ai_commit() {
    in_git_repo || { log_error "Not a git repository."; return 1; }
    action_install_opencode || return 1
    local msgfile msg id=()
    [ -z "$(git status --porcelain)" ] && { log_warn "Nothing to commit."; return 0; }
    git add -A
    msgfile="$(git rev-parse --git-dir)/repodir-commit-msg"; rm -f "$msgfile"
    log_info "Asking OpenCode for a commit message..."
    oc_run "Look at the staged changes (run: git diff --cached). Write a concise Conventional Commits message (subject <= 72 chars, optional short body) and save it to the file '$msgfile'. Do NOT run git commit and do not modify any other file."
    if [ -s "$msgfile" ]; then
        msg=$(cat "$msgfile"); echo "----"; echo "$msg"; echo "----"
        if confirm_or_yes "Commit with this message?" y; then
            [ -z "$(git config user.email)" ] && id=(-c user.name="repodir" -c user.email="repodir@localhost")
            git ${id[@]+"${id[@]}"} commit -q -F "$msgfile" && log_success "Committed."
        fi
        rm -f "$msgfile"
    else
        log_error "OpenCode did not produce a message (is a provider configured?). Changes are staged; commit manually."
        return 1
    fi
}

action_ai_build_fix() {
    local log="${1:-$BUILD_LOG_DIR/last.log}" spec="${2:-}" tail
    [ -f "$log" ] || { log_error "No build log found. Run a build first."; return 1; }
    tail=$(tail -n 120 "$log")
    ai_task "build-fix" "fix: repair build" "The project build failed. Diagnose the root cause from this log and fix the project so it builds. Make the smallest change that fixes it (config, dependency versions, code), do not touch unrelated files, and explain the cause at the end.

BUILD LOG (last 120 lines):
$tail" || return 1
    if [ -n "$spec" ] && [ "$INTERACTIVE" = true ] && confirm "Re-run the build now ($spec) on the fix branch?" y; then action_build "$spec"; fi
}

# ==============================================================================
# CI TEMPLATE / GIT HOOK / PLUGINS / SERVE / CLEAN
# ==============================================================================
action_init_ci() {
    mkdir -p .github/workflows || return 1
    local f=".github/workflows/repodir.yml"
    [ -f "$f" ] && ! confirm_or_yes "$f exists. Overwrite?" n && return 0
    cat > "$f" <<'EOF'
name: repodir audit

on:
  push:
    branches: [main, master]
  pull_request:
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history so the git-history secret scan works
      - name: Run repodir (fails the job when secrets are found)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: curl -fsSL __SELF_URL__ | bash -s -- --yml --audit --full --export html,json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: repodir-reports
          path: ~/.repodir/reports
EOF
    sed "s|__SELF_URL__|$SELF_URL|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    log_success "Wrote $f (commit it to enable the audit in GitHub Actions)."
}

action_install_hook() {
    in_git_repo || { log_error "Not a git repository."; return 1; }
    local hook; hook="$(git rev-parse --git-dir)/hooks/pre-commit"
    mkdir -p "$(dirname "$hook")"
    if [ -f "$hook" ] && ! grep -q 'repodir pre-commit' "$hook"; then
        confirm_or_yes "A different pre-commit hook exists. Back it up and replace?" n || return 1
        cp -f "$hook" "$hook.bak"
    fi
    {
        printf '%s\n' '#!/usr/bin/env bash' '# repodir pre-commit: blocks commits that add secrets'
        printf "regex='%s'\n" "$SECRET_REGEX"
        cat <<'EOF'
hits=$(git diff --cached -U0 --no-color | grep '^+' | grep -v '^+++' | grep -Eio -e "$regex" | head -5)
if [ -n "$hits" ]; then
  echo "repodir: commit blocked - possible secret(s) in staged changes:" >&2
  printf '%s\n' "$hits" | cut -c1-6 | sed 's/$/...[redacted]/' >&2
  echo "Remove them (or bypass once with: git commit --no-verify)." >&2
  exit 1
fi
exit 0
EOF
    } > "$hook"
    chmod +x "$hook"; log_success "Installed pre-commit secret guard: $hook"
}

action_remove_hook() {
    in_git_repo || { log_error "Not a git repository."; return 1; }
    local hook; hook="$(git rev-parse --git-dir)/hooks/pre-commit"
    if [ -f "$hook" ] && grep -q 'repodir pre-commit' "$hook"; then
        rm -f "$hook"; [ -f "$hook.bak" ] && mv "$hook.bak" "$hook"; log_success "Hook removed."
    else log_info "No repodir hook installed."; fi
}

load_plugins() {
    local f; [ -d "$PLUGIN_DIR" ] || return 0
    for f in "$PLUGIN_DIR"/*.sh; do [ -f "$f" ] && . "$f"; done
    return 0
}
action_plugins() {
    echo "Plugin dir: $PLUGIN_DIR"
    ls -1 "$PLUGIN_DIR"/*.sh 2>/dev/null | sed 's|.*/|  |; s|\.sh$||' || true
    declare -F | awk '{print $3}' | grep '^repodir_cmd_' | sed 's/^repodir_cmd_/  command: /; s/_/-/g'
}
action_new_plugin() {
    local n="${1:-}" fn
    ensure_arg n "$n" "Plugin name (letters, digits, -): " || return 1
    case "$n" in *[!A-Za-z0-9-]*|"") log_error "Invalid name."; return 1 ;; esac
    mkdir -p "$PLUGIN_DIR"; fn="repodir_cmd_${n//-/_}"
    [ -f "$PLUGIN_DIR/$n.sh" ] && { log_error "Plugin exists: $PLUGIN_DIR/$n.sh"; return 1; }
    cat > "$PLUGIN_DIR/$n.sh" <<EOF
# repodir plugin: $n   (usable as: repodir --plugin $n [args]  or inside the repodir shell: $n [args])
$fn() {
    echo "Hello from the $n plugin! args: \$*"
    echo "Current repo dir: \$PWD  | target: \$TARGET_REPO"
}
EOF
    log_success "Created $PLUGIN_DIR/$n.sh"
}
action_plugin() {
    local n="${1:-}" fn; shift
    [ -n "$n" ] || { log_error "Usage: --plugin <name> [args]"; return 1; }
    fn="repodir_cmd_${n//-/_}"
    declare -F "$fn" >/dev/null 2>&1 || { log_error "Plugin command not found: $n (see: repodir --plugins)"; return 1; }
    "$fn" "$@"
}

action_reports() {
    if ls "$REPORT_DIR"/* >/dev/null 2>&1; then ls -1t "$REPORT_DIR"/* | head -n 40; else echo "No reports yet."; fi
}
action_serve() {
    need python3 || return 1
    local port="${1:-8765}"
    mkdir -p "$REPORT_DIR"
    log_info "Serving reports at http://127.0.0.1:$port  (Ctrl+C to stop)"
    open_url "http://127.0.0.1:$port"
    ( cd "$REPORT_DIR" && python3 -m http.server "$port" --bind 127.0.0.1 )
}
action_clean() {
    local days="${1:-30}"
    case "$days" in ''|*[!0-9]*) log_error "Usage: clean [days]"; return 1 ;; esac
    local n; n=$(find "$REPORT_DIR" "$BUILD_LOG_DIR" -type f -mtime +"$days" 2>/dev/null | wc -l | tr -d ' ')
    find "$REPORT_DIR" "$BUILD_LOG_DIR" -type f -mtime +"$days" -delete 2>/dev/null
    log_success "Removed $n report/log file(s) older than $days days."
}

# ==============================================================================
# HELP
# ==============================================================================
FLAGS_ALL="-h --help -v --version -t --target -k --key -y --yes --yml --profile --profiles --model --branch --shallow --full --export --notify --save-baseline --keep --from --clone --audit --ai-audit --scan --history-scan --deps --outdated --audit-diff --ai-review --detect --suggest --build --tests --release --ai-fix --ai-update --deps-update --ai-docs --ai-tests --ai-changelog --ai-explain --ai-commit --ai-build-fix --ai --unzip-to-root --repos --repo-add --repo-rm --audit-all --pull-all --pick --gh-list --gh-info --notify-test --notify-config --init-ci --install-hook --remove-hook --reports --serve --clean --config --plugins --plugin --new-plugin --shell --install --update --uninstall --doctor --checksum --completion"

show_help() {
cat <<EOF
REPODIR v$VERSION - Repository Auditor, Builder & AI Maintainer (by Hunter Zen RU)

Usage:
  repodir [options]                     (no options = interactive menu)
  curl -fsSL $SELF_URL | bash -s -- [options]

SOURCE
  -t, --target <repo>        Target repo (owner/repo or URL)
      --from <path|zip|repo> Work on a local folder, a .zip, or a GitHub repo
      --clone                Clone or pull the target (--branch X, --shallow)
  -k, --key <token>          GitHub token (prefer env GITHUB_TOKEN; argv shows in history)
      --profile <name>       Separate token / repos / reports / workspace

AUDIT
      --audit [dir]          Quick audit: secrets, sensitive files, CI/Docker/IaC, hygiene, score A-F
      --full                 (modifier) add git-history scan, dependency CVEs, GitHub facts
      --export html,json,md  (modifier) extra report formats
      --save-baseline        (modifier) save results; later audits show the delta
      --scan [dir]           Secret scan only          --history-scan [dir]  Scan all git history
      --deps [dir]           Dependency vulnerabilities (npm/pip/go/cargo tools + OSV.dev)
      --outdated             List outdated dependencies
      --audit-diff [ref]     Audit only what changed since ref/merge-base
      --audit-all            Audit every saved repo and print a ranking table
      --notify               (modifier) send the summary to Slack/Discord/Telegram

BUILD  (detects the project type and suggests builds)
      --detect               Show detected project types and ready/missing toolchains
      --build [type:target]  e.g. android:debug  flutter:apk  go:lw  go:cross  rust:win-gnu
                             python:exe  dotnet:single  electron:both  node-cli:pkg  docker:image
      --tests                Run the detected test command
      --release <tag>        Upload ./dist/* to a GitHub release (gh)

AI (OpenCode, always on a safe git branch)
      --ai-audit [dir]       Read-only AI audit report      --ai-review [ref]   AI code review of a diff
      --ai-fix               Fix the audit findings         --ai-update         Update deps + fix breakage + test
      --deps-update          Update deps with native tools  --ai-build-fix      Fix the last failed build
      --ai-docs  --ai-tests  --ai-changelog  --ai-explain   --ai-commit
      --ai "<task>"          Any custom task                --model <p/model>   Choose the model
  -y, --yes                  Auto-approve confirmations (required for headless AI tasks)

REPOS / GITHUB
      --repos  --repo-add <r>  --repo-rm <r>  --pull-all  --pick
      --gh-list              Pick from your GitHub repos       --gh-info [owner/repo]

TOOLS
      --unzip-to-root [pattern] [--keep]    --init-ci (GitHub Actions workflow)
      --install-hook | --remove-hook        (pre-commit secret guard)
      --reports  --serve [port]  --clean [days]
      --config [KEY=VALUE]  --notify-config  --notify-test
      --plugins  --new-plugin <name>  --plugin <name> [args]
      --shell                Open the repodir shell
      --yml                  Headless/CI mode: no prompts; default = clone + full audit; exit 2 on secrets

MAINTENANCE
      --install  --update (SHA-256 verified)  --uninstall  --doctor  --checksum  --completion
  -v, --version   -h, --help

Examples:
  repodir -t owner/repo --clone --audit --full --export html
  repodir --from ./myapp --detect
  repodir --from owner/app --build android:debug
  repodir --from ./gocli --build go:lw
  repodir -t owner/repo --clone --ai-update --yes
  curl -fsSL $SELF_URL | bash -s -- --yml --audit --full
EOF
}

# ==============================================================================
# COMMAND DISPATCHER (shared by CLI flags, menus and the interactive shell)
# ==============================================================================
dispatch() {
    local cmd="$1"; shift
    case "$cmd" in
        clone)          action_clone "$@" ;;
        from)           action_from "$@" ;;
        audit)          action_audit "${1:-.}" ;;
        baseline)       SAVE_BASELINE=true; action_audit "${1:-.}"; SAVE_BASELINE=false ;;
        scan)           action_scan_secrets "${1:-.}" ;;
        history-scan)   action_history "${1:-.}" ;;
        deps)           action_deps "${1:-.}" ;;
        outdated)       action_outdated ;;
        audit-diff)     action_audit_diff "$@" ;;
        audit-all)      action_audit_all ;;
        ai-audit)       action_ai_audit "${1:-.}" ;;
        ai-review)      action_ai_review "$@" ;;
        ai-fix)         action_ai_fix ;;
        ai-update)      action_ai_update ;;
        deps-update)    action_deps_update ;;
        ai-docs|ai-tests|ai-changelog|ai-explain) action_ai_preset "$cmd" ;;
        ai-commit)      action_ai_commit ;;
        ai-build-fix)   action_ai_build_fix "$@" ;;
        ai)             action_ai_task "$*" ;;
        detect|suggest) action_detect "${1:-.}" ;;
        build)          action_build "$@" ;;
        tests)          action_tests ;;
        release)        action_release "$@" ;;
        unzip-root)
            local keep="$KEEP_ZIP" pat="" w
            for w in "$@"; do case "$w" in --keep) keep=true ;; *) pat="$w" ;; esac; done
            action_unzip_to_root "${pat:-*.zip}" "$keep" ;;
        opencode)       action_opencode ;;
        repos)          action_repo_list ;;
        repo-add)       action_repo_add "$@" ;;
        repo-rm)        action_repo_rm "$@" ;;
        pull-all)       action_pull_all ;;
        pick)           action_repo_pick ;;
        gh-list)        action_gh_list ;;
        gh-info)        action_gh_info "$@" ;;
        notify-test)    notify_send "repodir v$VERSION test notification from $(hostname 2>/dev/null)" ;;
        notify-config)  action_notify_config ;;
        init-ci)        action_init_ci ;;
        install-hook)   action_install_hook ;;
        remove-hook)    action_remove_hook ;;
        reports)        action_reports ;;
        serve)          action_serve "$@" ;;
        clean)          action_clean "$@" ;;
        config)         action_config "$@" ;;
        plugins)        action_plugins ;;
        plugin)         action_plugin "$@" ;;
        new-plugin)     action_new_plugin "$@" ;;
        shell)          launch_custom_shell ;;
        self-install)   install_system ;;
        update)         action_update ;;
        uninstall)      action_uninstall ;;
        doctor)         action_doctor ;;
        checksum)       action_checksum ;;
        completion)     completion_script ;;
        profiles)       action_profiles ;;
        token)          GPH_KEY=""; prompt_for_key ;;
        target)         if [ -n "$*" ]; then TARGET_REPO="$*"; else ask TARGET_REPO "Target repo (owner/repo or URL): " || return 1; fi
                        save_config; log_success "Target: $TARGET_REPO" ;;
        model)          if [ -n "$*" ]; then AI_MODEL="$*"; else ask AI_MODEL "OpenCode model (provider/model, blank = default): " || return 1; fi
                        save_config; log_success "Model: ${AI_MODEL:-default}" ;;
        format)         EXPORT_FMTS="${1:-}"; log_info "Extra export formats: ${EXPORT_FMTS:-none}" ;;
        full)           case "${1:-on}" in off|false|0) AUDIT_FULL=false ;; *) AUDIT_FULL=true ;; esac; log_info "Full audit mode: $AUDIT_FULL" ;;
        *)  local fn="repodir_cmd_${cmd//-/_}"
            if declare -F "$fn" >/dev/null 2>&1; then "$fn" "$@"; else return 127; fi ;;
    esac
}

# ==============================================================================
# CUSTOM INTERACTIVE SHELL
# ==============================================================================
shell_help() {
cat <<'EOF'
  SOURCE   target <repo> | clone [repo] | from <path|zip|repo> | pick | gh-list | repos
  AUDIT    audit [dir] | full on|off | format html,json | baseline | scan | history-scan | deps
           outdated | audit-diff [ref] | audit-all | gh-info
  BUILD    detect | build [type:target] | tests | release <tag>
  AI       ai-audit | ai-review [ref] | ai-fix | ai-update | deps-update | ai-build-fix
           ai-docs | ai-tests | ai-changelog | ai-explain | ai-commit | ai "<task>" | opencode
  TOOLS    unzip-root [pat] [--keep] | init-ci | install-hook | remove-hook | reports | serve
           clean | config [K=V] | model | token | notify-config | notify-test | plugins | doctor
  OTHER    status | edit <file> | update | self-install | clear | help | exit
  Anything else runs as a normal shell command (ls, cd, grep, git ...).
EOF
}

launch_custom_shell() {
    if [ "$INTERACTIVE" != true ]; then log_error "No interactive terminal available."; return 1; fi
    clear_screen
    echo "=================================================================="
    echo " REPODIR v$VERSION - AUDITOR SHELL      profile: $PROFILE"
    echo " Working Directory: $(pwd)"
    echo " Type 'help' for commands, 'exit' to leave."
    echo "=================================================================="

    set -o history
    HISTFILE="$HIST_FILE"; history -r 2>/dev/null
    trap 'echo; echo "(type exit to leave)"' INT

    local line cmd args rc ed
    while true; do
        IFS= read -e -r -p "repodir:$(basename "$PWD")\$ " line <"$TTY_IN" || { echo; break; }
        [ -z "$line" ] && continue
        history -s "$line"
        cmd="${line%% *}"; args=""
        [ "$line" != "$cmd" ] && args="${line#* }"

        case "$cmd" in
            help)       shell_help ;;
            status|git-status) git status 2>&1 || echo "Not a git repository." ;;
            edit)
                if [ -z "$args" ]; then echo "Specify a filename."
                else
                    ed="${EDITOR:-}"; [ -z "$ed" ] && { command -v nano >/dev/null 2>&1 && ed=nano || ed=vi; }
                    $ed "$args"
                fi ;;
            clear)      clear_screen ;;
            exit|quit)  echo "Exiting REPODIR shell."; break ;;
            ai)         dispatch ai "$args" ;;
            *)
                dispatch "$cmd" $args; rc=$?
                [ "$rc" -eq 127 ] && eval "$line"   # not ours: pass through to the system shell
                ;;
        esac
    done
    history -w 2>/dev/null
    trap - INT
    return 0
}

# ==============================================================================
# MENUS
# ==============================================================================
menu_header() {
    clear_screen
    echo "===================================================="
    echo " REPODIR v$VERSION        profile: $PROFILE"
    echo " Repository: ${TARGET_REPO:-Not Selected}"
    echo " Directory:  $(pwd)"
    echo " Token: $([ -n "$GPH_KEY" ] && echo set || echo "not set")   Model: ${AI_MODEL:-default}   Full audit: $AUDIT_FULL"
    echo "===================================================="
}

# submenu "Title" "label|command args" ...
submenu() {
    local title="$1"; shift
    local labels=() cmds=() it choice i l
    for it in "$@"; do labels+=("${it%%|*}"); cmds+=("${it#*|}"); done
    while true; do
        menu_header; echo " $title"; echo
        i=1; for l in "${labels[@]}"; do printf ' %2d) %s\n' "$i" "$l"; i=$((i+1)); done
        echo "  0) Back"
        ask choice "Choose: " || return 0
        case "$choice" in
            0|q|b|"") return 0 ;;
            *[!0-9]*) log_warn "Invalid choice."; sleep 1; continue ;;
        esac
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#labels[@]}" ]; then
            echo; dispatch ${cmds[$((choice-1))]}; echo; pause
        else log_warn "Invalid choice."; sleep 1; fi
    done
}

launch_menu_interface() {
    if [ "$INTERACTIVE" != true ]; then show_help; return 0; fi
    local choice
    while true; do
        menu_header
        echo " 1) Repository & GitHub"
        echo " 2) Audit & security"
        echo " 3) Build (APK / Windows / Linux / ...)"
        echo " 4) AI maintenance (OpenCode)"
        echo " 5) Tools (zip, CI, hooks, plugins, notifications)"
        echo " 6) Settings & maintenance"
        echo " 7) Custom interactive shell"
        echo " 0) Exit"
        echo "===================================================="
        ask choice "Choose [0-7]: " || break
        case "$choice" in
            1) submenu "Repository & GitHub" \
                 "Set target repository|target" "Clone / pull target|clone" \
                 "Use a local folder / zip / repo (--from)|from" \
                 "Pick from my GitHub repos|gh-list" "Pick from saved repos|pick" \
                 "List saved repos|repos" "Save target to repo list|repo-add" \
                 "Pull all saved repos|pull-all" "GitHub info (issues, PRs, alerts)|gh-info" ;;
            2) submenu "Audit & security" \
                 "Quick audit (current dir)|audit ." "Full audit (history + CVEs + GitHub)|full on" \
                 "Quick mode again|full off" "Export HTML + JSON reports|format html,json" \
                 "Save baseline (track progress)|baseline" "Secret scan|scan" \
                 "Git history secret scan|history-scan" "Dependency vulnerabilities|deps" \
                 "Outdated dependencies|outdated" "Audit only recent changes|audit-diff" \
                 "Audit ALL saved repos|audit-all" "List reports|reports" "Serve reports in browser|serve" ;;
            3) submenu "Build" \
                 "Detect project type + suggestions|detect" "Build (guided)|build" \
                 "Run tests|tests" "Publish ./dist to a GitHub release|release" ;;
            4) submenu "AI maintenance (OpenCode)" \
                 "AI audit (read-only report)|ai-audit" "AI fix audit findings|ai-fix" \
                 "AI update dependencies + fix breakage|ai-update" "Update deps with native tools|deps-update" \
                 "AI review recent changes|ai-review" "AI fix last failed build|ai-build-fix" \
                 "AI refresh docs (README)|ai-docs" "AI add tests|ai-tests" \
                 "AI changelog|ai-changelog" "AI architecture overview|ai-explain" \
                 "AI commit message + commit|ai-commit" "Custom AI task|ai" \
                 "Open OpenCode session|opencode" "Choose AI model|model" ;;
            5) submenu "Tools" \
                 "Unzip newest archive here|unzip-root" "Create GitHub Actions workflow|init-ci" \
                 "Install pre-commit secret guard|install-hook" "Remove pre-commit guard|remove-hook" \
                 "Configure notifications|notify-config" "Send test notification|notify-test" \
                 "New plugin|new-plugin" "List plugins|plugins" "Clean old reports/logs|clean" ;;
            6) submenu "Settings & maintenance" \
                 "Set / update GitHub token|token" "Show settings|config" "Profiles|profiles" \
                 "Install 'repodir' command|self-install" "Update repodir|update" \
                 "Doctor (check tools)|doctor" "Uninstall|uninstall" ;;
            7) launch_custom_shell ;;
            0|q|exit) return 0 ;;
            *) log_warn "Invalid choice: $choice"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# ARGUMENT PARSER (collects actions, runs them in order afterwards)
# ==============================================================================
ACT_SHIFT=1
add_opt() {  # add_opt name remaining-args...   optional argument
    local name="$1"; shift
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then ACTIONS+=("$name:$1"); ACT_SHIFT=2; else ACTIONS+=("$name:"); ACT_SHIFT=1; fi
}
add_req() {  # add_req name flag remaining-args...   required argument
    local name="$1" flag="$2"; shift 2
    [ $# -gt 0 ] || die "$flag needs a value"
    ACTIONS+=("$name:$1"); ACT_SHIFT=2
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    show_help; exit 0 ;;
            -v|--version) echo "repodir $VERSION"; exit 0 ;;
            -t|--target)  [ $# -ge 2 ] || die "$1 needs a value"; TARGET_REPO="$2"; TARGET_FROM_CLI=true; shift 2 ;;
            -k|--key)     [ $# -ge 2 ] || die "$1 needs a value"; GPH_KEY="$2"; shift 2 ;;
            --profile)    shift 2 ;;                                   # handled before config load
            --model)      [ $# -ge 2 ] || die "$1 needs a value"; AI_MODEL="$2"; shift 2 ;;
            --branch)     [ $# -ge 2 ] || die "$1 needs a value"; CLONE_BRANCH="$2"; shift 2 ;;
            --export)     [ $# -ge 2 ] || die "$1 needs a value"; EXPORT_FMTS="$2"; shift 2 ;;
            -y|--yes)     ASSUME_YES=true; shift ;;
            --yml)        YML_MODE=true; shift ;;
            --keep)       KEEP_ZIP=true; shift ;;
            --full)       AUDIT_FULL=true; shift ;;
            --notify)     NOTIFY=true; shift ;;
            --shallow)    SHALLOW=true; shift ;;
            --save-baseline) SAVE_BASELINE=true; shift ;;
            --from)       add_req from "$@";            shift $ACT_SHIFT ;;
            --ai)         add_req ai "$@";              shift $ACT_SHIFT ;;
            --release)    add_req release "$@";         shift $ACT_SHIFT ;;
            --repo-add)   add_req repo-add "$@";        shift $ACT_SHIFT ;;
            --repo-rm)    add_req repo-rm "$@";         shift $ACT_SHIFT ;;
            --new-plugin) add_req new-plugin "$@";      shift $ACT_SHIFT ;;
            --plugin)     [ $# -ge 2 ] || die "--plugin needs a name"; shift; ACTIONS+=("plugin:$*"); set --; break ;;
            --audit)        add_opt audit "${@:2}";        shift $ACT_SHIFT ;;
            --ai-audit)     add_opt ai-audit "${@:2}";     shift $ACT_SHIFT ;;
            --scan)         add_opt scan "${@:2}";         shift $ACT_SHIFT ;;
            --history-scan) add_opt history-scan "${@:2}"; shift $ACT_SHIFT ;;
            --deps)         add_opt deps "${@:2}";         shift $ACT_SHIFT ;;
            --audit-diff)   add_opt audit-diff "${@:2}";   shift $ACT_SHIFT ;;
            --ai-review)    add_opt ai-review "${@:2}";    shift $ACT_SHIFT ;;
            --detect|--suggest) add_opt detect "${@:2}";   shift $ACT_SHIFT ;;
            --build)        add_opt build "${@:2}";        shift $ACT_SHIFT ;;
            --gh-info)      add_opt gh-info "${@:2}";      shift $ACT_SHIFT ;;
            --serve)        add_opt serve "${@:2}";        shift $ACT_SHIFT ;;
            --clean)        add_opt clean "${@:2}";        shift $ACT_SHIFT ;;
            --config)       add_opt config "${@:2}";       shift $ACT_SHIFT ;;
            --unzip-to-root) add_opt unzip-root "${@:2}";  shift $ACT_SHIFT ;;
            --clone|--outdated|--tests|--ai-fix|--ai-update|--deps-update|--ai-docs|--ai-tests|--ai-changelog|--ai-explain|--ai-commit|--ai-build-fix|--audit-all|--pull-all|--pick|--gh-list|--repos|--notify-test|--notify-config|--init-ci|--install-hook|--remove-hook|--reports|--plugins|--shell|--update|--uninstall|--doctor|--checksum|--completion|--profiles)
                ACTIONS+=("${1#--}:"); shift ;;
            --install)    ACTIONS+=("self-install:"); shift ;;
            *) log_error "Unknown argument: $1 (see --help)"; exit 1 ;;
        esac
    done
}

run_actions() {
    local a name arg rc=0 r
    for a in ${ACTIONS[@]+"${ACTIONS[@]}"}; do
        name="${a%%:*}"; arg="${a#*:}"; r=0
        if [ "$name" = plugin ]; then dispatch plugin $arg; r=$?
        elif [ -n "$arg" ]; then dispatch "$name" "$arg"; r=$?
        else dispatch "$name"; r=$?; fi
        [ "$r" -eq 127 ] && { log_error "Unknown action: $name"; r=1; }
        [ "$r" -gt "$rc" ] && rc=$r
    done
    return $rc
}

# ==============================================================================
# MAIN (wrapped so a truncated `curl | bash` download can never run half a script)
# ==============================================================================
main() {
    local i p=("$@") rc
    for ((i = 0; i < ${#p[@]}; i++)); do
        [ "${p[$i]}" = "--profile" ] && PROFILE="${p[$((i+1))]:-default}"
    done
    detect_os
    setup_dirs
    load_config
    [ -z "$GPH_KEY" ] && GPH_KEY="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    [ -z "$AI_MODEL" ] && AI_MODEL="${REPODIR_MODEL:-}"
    load_plugins
    parse_args "$@"

    # ---- Headless / CI ----------------------------------------------------------
    if [ "$YML_MODE" = true ]; then
        INTERACTIVE=false
        log_info "CI/CD mode (--yml): prompts disabled."
        if [ ${#ACTIONS[@]} -eq 0 ]; then
            [ -n "$TARGET_REPO" ] && ACTIONS+=("clone:")
            ACTIONS+=("audit:"); AUDIT_FULL=true
        fi
        run_actions; rc=$?
        [ "$rc" -eq 2 ] && log_warn "Findings detected (secrets: $SECRET_HITS)."
        exit $rc
    fi

    # ---- Explicit actions ---------------------------------------------------------
    if [ ${#ACTIONS[@]} -gt 0 ]; then run_actions; exit $?; fi

    # ---- Interactive --------------------------------------------------------------
    if [ "$INTERACTIVE" != true ]; then
        log_warn "No interactive terminal detected."
        show_help; exit 0
    fi
    check_update_notice
    if [ ! -x "$BIN_DIR/repodir" ] && [ ! -f "$ROOT_DIR/.noprompt" ]; then
        if confirm "Install 'repodir' as a command in $BIN_DIR (with tab-completion)?" y; then install_system
        else mkdir -p "$ROOT_DIR" && : > "$ROOT_DIR/.noprompt"; fi
    fi
    if [ "$TARGET_FROM_CLI" = true ] && [ -n "$TARGET_REPO" ]; then
        log_info "Targeted startup: $TARGET_REPO"
        [ -z "$GPH_KEY" ] && prompt_for_key
        action_clone || log_warn "Continuing without a local clone."
        launch_custom_shell
    else
        launch_menu_interface
    fi
}

main "$@"
