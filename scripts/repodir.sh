#!/usr/bin/env bash
# ==============================================================================
# PROJECT     : REPODIR v2 (Repository Auditor)
# DEVELOPER   : Hunter Zen RU
# DESCRIPTION : Cross-platform workspace manager, custom interactive shell and
#               OpenCode AI audit pipeline orchestrator.
#
# RUN         : curl -fsSL https://hunter-zen-ru.github.io/scripts/repodir.sh | bash
# WITH ARGS   : curl -fsSL https://hunter-zen-ru.github.io/scripts/repodir.sh | bash -s -- -t owner/repo --audit
# ==============================================================================
# NOTE: no `set -e` / `set -u` on purpose. This is an interactive tool: one failed
# command (e.g. a typo in the custom shell) must never kill the whole session.
set -o pipefail

VERSION="2.0.0"
SELF_URL="https://hunter-zen-ru.github.io/scripts/repodir.sh"
OPENCODE_INSTALL_URL="https://opencode.ai/install"

CONFIG_DIR="${REPODIR_HOME:-$HOME/.repodir}"
CONFIG_FILE="$CONFIG_DIR/conf"
REPORT_DIR="$CONFIG_DIR/reports"
HIST_FILE="$CONFIG_DIR/history"
BIN_DIR="$HOME/.local/bin"
WORKSPACE="${REPODIR_WORKSPACE:-$HOME/repodir-workspace}"
RC_START="# >>> repodir >>>"
RC_END="# <<< repodir <<<"

# Global state
TARGET_REPO=""
GPH_KEY=""
YML_MODE=false
KEEP_ZIP=false
UNZIP_PATTERN="*.zip"
TARGET_FROM_CLI=false
SECRET_HITS=0
ACTIONS=()

# ==============================================================================
# TERMINAL / LOGGING HELPERS
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

# Input: when launched via `curl | bash`, stdin is the script itself, so every
# `read` must come from the real terminal (/dev/tty) instead.
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
        echo
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

pause() { local d; ask d "Press enter to return..." || true; }
clear_screen() { [ -t 1 ] && clear; return 0; }

open_url() {
    if   command -v xdg-open  >/dev/null 2>&1; then xdg-open  "$1" >/dev/null 2>&1 &
    elif command -v open      >/dev/null 2>&1; then open      "$1" >/dev/null 2>&1 &
    elif command -v wslview   >/dev/null 2>&1; then wslview   "$1" >/dev/null 2>&1 &
    else echo "Please navigate to: $1"; fi
    return 0
}

need() {  # need cmd [cmd...] -> fails with message if any missing
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || { log_error "Required tool not found: $c"; return 1; }
    done
}

# ==============================================================================
# CONFIG (parsed safely, never `source`d, token file is chmod 600)
# ==============================================================================
load_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    local k v
    while IFS='=' read -r k v; do
        v="${v%\"}"; v="${v#\"}"
        case "$k" in
            TARGET_REPO) TARGET_REPO="$v" ;;
            GPH_KEY)     GPH_KEY="$v" ;;
        esac
    done < "$CONFIG_FILE"
}

save_config() {
    mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR" 2>/dev/null
    ( umask 077; printf 'TARGET_REPO=%s\nGPH_KEY=%s\n' "$TARGET_REPO" "$GPH_KEY" > "$CONFIG_FILE" )
    chmod 600 "$CONFIG_FILE" 2>/dev/null
}

prompt_for_key() {
    if [ -n "$GPH_KEY" ]; then return 0; fi
    log_warn "GitHub token missing (needed for private repos / higher rate limits)."
    if confirm "Open the GitHub token page in your browser?" y; then
        open_url "https://github.com/settings/personal-access-tokens/new"
    fi
    ask GPH_KEY "🔑 Enter your GitHub Personal Key (input hidden, enter to skip): " silent || true
    if [ -n "$GPH_KEY" ]; then save_config; log_success "Token saved to $CONFIG_FILE (chmod 600)."; fi
    return 0
}

# ==============================================================================
# GIT (token is passed via env config header, NOT embedded in the URL,
#      so it never ends up in .git/config or the process list)
# ==============================================================================
normalize_repo() {
    case "$1" in
        http://*|https://*|git@*|ssh://*|file://*|/*|./*|../*) printf '%s' "$1" ;;
        */*) printf 'https://github.com/%s.git' "${1%.git}" ;;
        *)   printf '%s' "$1" ;;
    esac
}

repo_name() {
    local n="${1%/}"
    n="${n##*/}"; n="${n##*:}"
    printf '%s' "${n%.git}"
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

action_clone() {
    need git || return 1
    local url dest
    url=$(normalize_repo "${1:-$TARGET_REPO}")
    [ -n "$url" ] || { log_error "No repository set. Use -t owner/repo."; return 1; }
    dest="${2:-$WORKSPACE/$(repo_name "$url")}"

    if [ -d "$dest/.git" ]; then
        log_info "Repository exists, pulling latest: $dest"
        git_auth -C "$dest" pull --ff-only || log_warn "Pull failed (local changes or diverged history)."
    else
        mkdir -p "$(dirname "$dest")" || return 1
        log_info "Cloning $url -> $dest"
        git_auth clone "$url" "$dest" || { log_error "Clone failed. Check URL / token."; return 1; }
    fi
    cd "$dest" || return 1
    log_success "Working directory: $(pwd)"
}

# ==============================================================================
# ZIP -> ROOT
# ==============================================================================
extract_zip() {  # extract_zip zipfile destdir
    if   command -v unzip   >/dev/null 2>&1; then unzip -o -q "$1" -d "$2"
    elif command -v bsdtar  >/dev/null 2>&1; then bsdtar -xf "$1" -C "$2"
    elif command -v python3 >/dev/null 2>&1; then python3 -m zipfile -e "$1" "$2"
    else log_error "Need one of: unzip, bsdtar, python3"; return 1; fi
}

action_unzip_to_root() {
    local pattern="${1:-*.zip}" keep="${2:-false}" f newest="" tmp src n
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

    # GitHub-style zips wrap everything in one folder: flatten it.
    src="$tmp"
    n=$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    if [ "$n" -eq 1 ]; then
        local only; only=$(find "$tmp" -mindepth 1 -maxdepth 1)
        [ -d "$only" ] && src="$only"
    fi

    cp -a "$src"/. ./ || { log_error "Copy failed."; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"

    if [ "$keep" = "false" ] && [ -f "$newest" ]; then
        rm -f "$newest"; log_info "Removed source archive."
    fi
    log_success "Unzip complete."
}

# ==============================================================================
# OPENCODE
# ==============================================================================
action_install_opencode() {
    export PATH="$HOME/.opencode/bin:$BIN_DIR:$PATH"
    if command -v opencode >/dev/null 2>&1; then
        log_success "OpenCode already installed: $(command -v opencode)"
        return 0
    fi
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

action_opencode() {
    action_install_opencode || return 1
    opencode
}

# ==============================================================================
# AUDIT ENGINE
# ==============================================================================
SECRET_REGEX='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|passwd|password|token)[^A-Za-z0-9]{1,4}[A-Za-z0-9/+_-]{16,}'

# Prints "file:line  abc123...[redacted]" - never prints the full secret.
scan_secrets_raw() {
    grep -rIEno -i --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv \
        -e "$SECRET_REGEX" "${1:-.}" 2>/dev/null |
    awk -F: '{ m=$0; sub(/^[^:]*:[^:]*:/, "", m); printf "%s:%s  %s...[redacted]\n", $1, $2, substr(m,1,6) }'
}

action_scan_secrets() {
    local dir="${1:-.}" hits count=0
    log_info "Scanning for hard-coded secrets in: $dir"
    hits=$(scan_secrets_raw "$dir")
    [ -n "$hits" ] && count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    SECRET_HITS=$count
    if [ "$count" -gt 0 ]; then
        log_warn "$count potential secret(s) found:"
        printf '%s\n' "$hits" | head -n 50
        [ "$count" -gt 50 ] && echo "... and $((count - 50)) more"
        return 2
    fi
    log_success "No obvious secrets found."
}

action_audit() {
    local dir="${1:-.}" name ts out hits count=0
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found: ${1:-.}"; return 1; }
    name=$(basename "$dir"); ts=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$REPORT_DIR" || return 1
    out="$REPORT_DIR/${name}-${ts}.md"
    log_info "Auditing $dir ..."

    hits=$(scan_secrets_raw "$dir")
    [ -n "$hits" ] && count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    SECRET_HITS=$count

    local prune=( -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/vendor/*' )
    chk() {
        local label="$1" f; shift
        for f in "$@"; do [ -e "$dir/$f" ] && { echo "- [x] $label"; return; }; done
        echo "- [ ] $label (missing)"
    }

    {
        echo "# REPODIR audit: $name"
        echo
        echo "- Generated: $(date -u +%FT%TZ)"
        echo "- Path: \`$dir\`"
        echo "- Tool: repodir v$VERSION"
        echo
        echo "## Overview"
        echo "- Files: $(find "$dir" -type f "${prune[@]}" | wc -l | tr -d ' ')"
        echo "- Size on disk: $(du -sk "$dir" 2>/dev/null | cut -f1) KB"
        if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "- Git branch: $(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
            echo "- Commits: $(git -C "$dir" rev-list --count HEAD 2>/dev/null)"
            echo "- Last commit: $(git -C "$dir" log -1 --format='%h %s (%an, %ar)' 2>/dev/null)"
            echo
            echo "## Top contributors"
            git -C "$dir" shortlog -sn HEAD 2>/dev/null | head -5 | sed 's/^/    /'
        fi
        echo
        echo "## File types (top 10)"
        find "$dir" -type f "${prune[@]}" | awk -F/ '{ n=split($NF,a,"."); print (n>1 ? a[n] : "(none)") }' \
            | sort | uniq -c | sort -rn | head -10 | sed 's/^/    /'
        echo
        echo "## Largest files"
        find "$dir" -type f "${prune[@]}" -exec du -k {} + 2>/dev/null | sort -rn | head -5 \
            | awk -F'\t' '{ printf "- %s (%s KB)\n", $2, $1 }'
        echo
        echo "## Dependency manifests"
        local m found=false
        for m in package.json requirements.txt pyproject.toml Pipfile Cargo.toml go.mod Gemfile pom.xml build.gradle composer.json; do
            find "$dir" -maxdepth 3 -name "$m" "${prune[@]}" 2>/dev/null | while IFS= read -r p; do echo "- ${p#$dir/}"; done
        done
        echo
        echo "## Hygiene"
        chk "README"     README.md README README.rst readme.md
        chk "LICENSE"    LICENSE LICENSE.md LICENSE.txt COPYING
        chk ".gitignore" .gitignore
        chk "SECURITY policy" SECURITY.md .github/SECURITY.md
        chk "CI workflows" .github/workflows .gitlab-ci.yml .circleci
        echo "- TODO/FIXME/HACK markers: $(grep -rIE --exclude-dir=.git --exclude-dir=node_modules 'TODO|FIXME|HACK|XXX' "$dir" 2>/dev/null | wc -l | tr -d ' ')"
        echo
        echo "## Sensitive files present"
        local risky
        risky=$(find "$dir" -type f \( -name '.env' -o -name '.env.*' -o -name 'id_rsa' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name '*.keystore' \) \
                ! -name '*.example' ! -name '*.sample' "${prune[@]}" 2>/dev/null)
        if [ -n "$risky" ]; then printf '%s\n' "$risky" | sed "s|^$dir/|- |"; else echo "- none"; fi
        echo
        echo "## Potential hard-coded secrets: $count"
        if [ "$count" -gt 0 ]; then printf '%s\n' "$hits" | head -n 100 | sed 's/^/    /'; else echo "- none detected"; fi
    } > "$out"

    cat "$out"
    echo
    log_success "Report saved: $out"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$out" >> "$GITHUB_STEP_SUMMARY"
    [ "$count" -gt 0 ] && return 2
    return 0
}

action_ai_audit() {
    local dir="${1:-.}" name ts out rc
    dir=$(cd "$dir" 2>/dev/null && pwd) || { log_error "Directory not found."; return 1; }
    action_install_opencode || return 1
    name=$(basename "$dir"); ts=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$REPORT_DIR" || return 1
    out="$REPORT_DIR/${name}-ai-${ts}.md"

    local prompt='You are a senior security and code-quality auditor. This is a READ-ONLY task: do NOT modify, create or delete any files. Audit this repository for: (1) security vulnerabilities and exposed secrets, (2) bugs and logic errors, (3) risky or outdated dependencies, (4) code quality and maintainability, (5) missing tests, CI and docs. Output a Markdown report with an executive summary, a findings table (severity, file:line, issue, recommended fix) and a prioritized action plan.'

    log_info "Running OpenCode AI audit (needs a configured provider: run 'opencode auth login' or export a provider API key)..."
    ( cd "$dir" && opencode run "$prompt" ) | tee "$out"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then log_error "OpenCode exited with code $rc."; return "$rc"; fi
    log_success "AI report saved: $out"
}

action_list_reports() {
    if ls "$REPORT_DIR"/*.md >/dev/null 2>&1; then ls -1t "$REPORT_DIR"/*.md; else echo "No reports yet."; fi
}

# ==============================================================================
# INSTALL / UPDATE / UNINSTALL / DOCTOR
# ==============================================================================
install_system() {
    mkdir -p "$CONFIG_DIR" "$BIN_DIR" || return 1
    chmod 700 "$CONFIG_DIR" 2>/dev/null
    local dest="$CONFIG_DIR/repodir" src="${BASH_SOURCE[0]:-}"

    # Piped from curl => no local file, so download a copy instead of `cp $0`.
    if [ -n "$src" ] && [ -f "$src" ] && [ -r "$src" ]; then
        [ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" = "$dest" ] || cp -f "$src" "$dest"
    else
        need curl || return 1
        curl -fsSL "$SELF_URL" -o "$dest" || { log_error "Could not download $SELF_URL"; return 1; }
    fi
    chmod +x "$dest"
    ln -sf "$dest" "$BIN_DIR/repodir"

    local rc added=false
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        if ! grep -qF "$RC_START" "$rc"; then
            printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n%s\n' "$RC_START" "$RC_END" >> "$rc"
            added=true
        fi
    done
    if [ "$added" = false ] && ! grep -qs "$RC_START" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; then
        case "${SHELL:-}" in */zsh) rc="$HOME/.zshrc" ;; *) rc="$HOME/.bashrc" ;; esac
        printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n%s\n' "$RC_START" "$RC_END" >> "$rc"
    fi
    log_success "Installed: $BIN_DIR/repodir  (open a new shell, then just run: repodir)"
}

action_update() {
    need curl || return 1
    local tmp dest="$CONFIG_DIR/repodir"
    tmp=$(mktemp) || return 1
    log_info "Fetching latest version from $SELF_URL"
    if ! curl -fsSL "$SELF_URL" -o "$tmp"; then rm -f "$tmp"; log_error "Download failed."; return 1; fi
    if ! bash -n "$tmp" 2>/dev/null; then rm -f "$tmp"; log_error "Downloaded script failed syntax check; keeping current version."; return 1; fi
    mkdir -p "$CONFIG_DIR"; cat "$tmp" > "$dest"; chmod +x "$dest"; rm -f "$tmp"
    ln -sf "$dest" "$BIN_DIR/repodir" 2>/dev/null
    log_success "Updated to: $(grep -m1 '^VERSION=' "$dest" | cut -d'"' -f2)"
}

action_uninstall() {
    confirm "Remove repodir, its config, token and reports?" n || { log_info "Cancelled."; return 0; }
    rm -f "$BIN_DIR/repodir"
    local rc tmp
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        [ -f "$rc" ] && grep -qF "$RC_START" "$rc" || continue
        tmp=$(mktemp)
        awk -v s="$RC_START" -v e="$RC_END" '$0==s{skip=1;next} $0==e{skip=0;next} !skip' "$rc" > "$tmp" && cat "$tmp" > "$rc"
        rm -f "$tmp"
    done
    rm -rf "$CONFIG_DIR"
    log_success "repodir removed. (Cloned repos in $WORKSPACE were left untouched.)"
}

action_doctor() {
    local t
    echo "repodir v$VERSION  |  bash ${BASH_VERSION}  |  OS: ${OSTYPE:-unknown}"
    for t in git curl unzip python3 opencode; do
        if command -v "$t" >/dev/null 2>&1; then printf '  [ok]      %s\n' "$t"; else printf '  [missing] %s\n' "$t"; fi
    done
    [ -n "$GPH_KEY" ] && echo "  [ok]      GitHub token configured" || echo "  [missing] GitHub token (optional)"
    [ "$INTERACTIVE" = true ] && echo "  [ok]      interactive terminal" || echo "  [info]    no terminal (headless mode only)"
    [ -x "$BIN_DIR/repodir" ] && echo "  [ok]      installed at $BIN_DIR/repodir" || echo "  [info]    not installed (run: --install)"
}

show_help() {
cat <<EOF
REPODIR v$VERSION - Repository Auditor (by Hunter Zen RU)

Usage:
  repodir [options]
  curl -fsSL $SELF_URL | bash -s -- [options]

Options:
  -t, --target <repo>      Target repo (owner/repo or full URL)
  -k, --key <token>        GitHub token for this run (prefer env GITHUB_TOKEN; CLI args show in shell history)
      --clone              Clone or pull the target repo
      --audit [dir]        Local audit report (files, git, hygiene, secrets)
      --ai-audit [dir]     OpenCode AI audit (read-only)
      --scan [dir]         Secret scan only
      --unzip-to-root [pattern] [--keep]
                           Extract newest zip into the current directory
      --reports            List saved reports
      --shell              Open the custom interactive shell
      --yml                Headless / CI mode (no prompts). Default: clone + audit,
                           exit code 2 if secrets are found
      --install            Install 'repodir' command into ~/.local/bin
      --update             Self-update from $SELF_URL
      --uninstall          Remove repodir
      --doctor             Check dependencies
  -v, --version            Print version
  -h, --help               Show this help

Examples:
  repodir -t torvalds/linux --clone --audit
  repodir -t owner/repo --yml --ai-audit
  repodir --unzip-to-root 'project*.zip' --keep
EOF
}

# ==============================================================================
# CUSTOM INTERACTIVE SHELL
# ==============================================================================
launch_custom_shell() {
    if [ "$INTERACTIVE" != true ]; then log_error "No interactive terminal available."; return 1; fi
    clear_screen
    echo "=================================================================="
    echo " REPODIR v$VERSION - AUDITOR SHELL"
    echo " Working Directory: $(pwd)"
    echo " Type 'help' for commands, 'exit' to leave."
    echo "=================================================================="

    set -o history
    HISTFILE="$HIST_FILE"; history -r 2>/dev/null
    trap 'echo; echo "(type exit to leave)"' INT

    local line cmd args w keep pat
    while true; do
        IFS= read -e -r -p "repodir:$(basename "$PWD")\$ " line <"$TTY_IN" || { echo; break; }
        [ -z "$line" ] && continue
        history -s "$line"
        cmd="${line%% *}"; args=""
        [ "$line" != "$cmd" ] && args="${line#* }"

        case "$cmd" in
            help)
                cat <<'EOF'
  clone [repo]            - Clone/pull a repo and cd into it (default: saved target)
  audit [dir]             - Local audit report
  ai-audit [dir]          - OpenCode AI audit
  scan [dir]              - Scan for hard-coded secrets
  unzip-root [pat] [--keep] - Extract newest zip into current dir
  opencode                - Start an OpenCode session
  status | git-status     - git status
  edit <file>             - Edit a file ($EDITOR, nano or vi)
  reports                 - List saved reports
  target <repo>           - Set + save the target repo
  token                   - Set + save the GitHub token
  update                  - Self-update repodir
  doctor                  - Check dependencies
  clear                   - Clear screen
  exit | quit             - Leave this shell
  (anything else runs as a normal shell command, e.g. ls, cd, grep)
EOF
                ;;
            clone)      action_clone $args ;;
            audit)      action_audit ${args:-.} ;;
            ai-audit)   action_ai_audit ${args:-.} ;;
            scan)       action_scan_secrets ${args:-.} ;;
            unzip-root)
                keep=false; pat=""
                for w in $args; do case "$w" in --keep) keep=true ;; *) pat="$w" ;; esac; done
                action_unzip_to_root "${pat:-*.zip}" "$keep"
                ;;
            opencode)   action_opencode ;;
            status|git-status) git status 2>&1 || echo "Not a git repository." ;;
            edit)
                if [ -z "$args" ]; then echo "Specify a filename."
                else
                    local ed="${EDITOR:-}"
                    [ -z "$ed" ] && { command -v nano >/dev/null 2>&1 && ed=nano || ed=vi; }
                    $ed "$args"
                fi
                ;;
            reports)    action_list_reports ;;
            target)     if [ -n "$args" ]; then TARGET_REPO="$args"; save_config; log_success "Target: $TARGET_REPO"; else echo "Target: ${TARGET_REPO:-none}"; fi ;;
            token)      GPH_KEY=""; prompt_for_key ;;
            update)     action_update ;;
            doctor)     action_doctor ;;
            clear)      clear_screen ;;
            exit|quit)  echo "Exiting REPODIR shell."; break ;;
            *)          eval "$line" ;;   # pass-through to the system shell
        esac
    done
    history -w 2>/dev/null
    trap - INT
    return 0
}

# ==============================================================================
# MENU INTERFACE
# ==============================================================================
launch_menu_interface() {
    if [ "$INTERACTIVE" != true ]; then show_help; return 0; fi
    local choice pat
    while true; do
        clear_screen
        echo "===================================================="
        echo " REPODIR v$VERSION - MAIN MENU"
        echo " Repository: ${TARGET_REPO:-Not Selected}"
        echo " Token:      $([ -n "$GPH_KEY" ] && echo set || echo not set)"
        echo "===================================================="
        echo " 1) Select / change target repository"
        echo " 2) Set / update GitHub key"
        echo " 3) Clone / pull target repository"
        echo " 4) Run local audit (in current directory)"
        echo " 5) Run OpenCode AI audit"
        echo " 6) Launch OpenCode session"
        echo " 7) Unzip archive to current folder"
        echo " 8) Custom interactive shell"
        echo " 9) Install 'repodir' command to PATH"
        echo "10) Update repodir"
        echo "11) Doctor (check dependencies)"
        echo " 0) Exit"
        echo "===================================================="
        ask choice "Choose [0-11]: " || break

        case "$choice" in
            1) ask TARGET_REPO "Target repo (owner/repo or URL): "; save_config ;;
            2) GPH_KEY=""; prompt_for_key; pause ;;
            3) action_clone; pause ;;
            4) action_audit .; pause ;;
            5) action_ai_audit .; pause ;;
            6) action_opencode ;;
            7) ask pat "Archive pattern (default: *.zip): "; action_unzip_to_root "${pat:-*.zip}" false; pause ;;
            8) launch_custom_shell ;;
            9) install_system; pause ;;
            10) action_update; pause ;;
            11) action_doctor; pause ;;
            0|q|exit) return 0 ;;
            *) log_warn "Invalid choice: $choice"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# ARGUMENT PARSER (collects actions first, runs them in order afterwards)
# ==============================================================================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    show_help; exit 0 ;;
            -v|--version) echo "repodir $VERSION"; exit 0 ;;
            -t|--target)  [ $# -ge 2 ] || die "$1 needs a value"; TARGET_REPO="$2"; TARGET_FROM_CLI=true; shift 2 ;;
            -k|--key)     [ $# -ge 2 ] || die "$1 needs a value"; GPH_KEY="$2"; shift 2 ;;
            --yml)        YML_MODE=true; shift ;;
            --keep)       KEEP_ZIP=true; shift ;;
            --clone)      ACTIONS+=("clone"); shift ;;
            --shell)      ACTIONS+=("shell"); shift ;;
            --reports)    ACTIONS+=("reports"); shift ;;
            --install)    ACTIONS+=("install"); shift ;;
            --update)     ACTIONS+=("update"); shift ;;
            --uninstall)  ACTIONS+=("uninstall"); shift ;;
            --doctor)     ACTIONS+=("doctor"); shift ;;
            --audit|--ai-audit|--scan)
                local a="${1#--}"; shift
                if [ $# -gt 0 ] && [[ "$1" != -* ]]; then ACTIONS+=("$a:$1"); shift; else ACTIONS+=("$a:."); fi
                ;;
            --unzip-to-root)
                shift
                if [ $# -gt 0 ] && [[ "$1" != -* ]]; then UNZIP_PATTERN="$1"; shift; fi
                ACTIONS+=("unzip")
                ;;
            *) log_error "Unknown argument: $1 (see --help)"; exit 1 ;;
        esac
    done
}

run_actions() {
    local a rc=0 r
    for a in ${ACTIONS[@]+"${ACTIONS[@]}"}; do
        r=0
        case "$a" in
            clone)       action_clone;                         r=$? ;;
            audit:*)     action_audit "${a#audit:}";           r=$? ;;
            ai-audit:*)  action_ai_audit "${a#ai-audit:}";     r=$? ;;
            scan:*)      action_scan_secrets "${a#scan:}";     r=$? ;;
            unzip)       action_unzip_to_root "$UNZIP_PATTERN" "$KEEP_ZIP"; r=$? ;;
            reports)     action_list_reports;                  r=$? ;;
            install)     install_system;                       r=$? ;;
            update)      action_update;                        r=$? ;;
            uninstall)   action_uninstall;                     r=$? ;;
            doctor)      action_doctor;                        r=$? ;;
            shell)       launch_custom_shell;                  r=$? ;;
        esac
        [ "$r" -gt "$rc" ] && rc=$r
    done
    return $rc
}

# ==============================================================================
# MAIN (everything is wrapped so a truncated `curl | bash` download can never
#       execute half a script)
# ==============================================================================
main() {
    load_config
    [ -z "$GPH_KEY" ] && GPH_KEY="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    parse_args "$@"

    # ---- Headless / CI mode ----------------------------------------------------
    if [ "$YML_MODE" = true ]; then
        INTERACTIVE=false
        log_info "CI/CD mode (--yml): prompts disabled."
        if [ ${#ACTIONS[@]} -eq 0 ]; then
            [ -n "$TARGET_REPO" ] && ACTIONS+=("clone")
            ACTIONS+=("audit:.")
        fi
        run_actions; local rc=$?
        [ "$rc" -eq 2 ] && log_warn "Findings detected (potential secrets: $SECRET_HITS)."
        exit $rc
    fi

    # ---- Explicit actions given on the command line ---------------------------
    if [ ${#ACTIONS[@]} -gt 0 ]; then
        run_actions; exit $?
    fi

    # ---- Interactive ----------------------------------------------------------
    if [ "$INTERACTIVE" != true ]; then
        log_warn "No interactive terminal detected."
        show_help; exit 0
    fi

    # Offer one-time install of the `repodir` command (instead of silently
    # editing shell rc files on every launch like v1 did).
    if [ ! -x "$BIN_DIR/repodir" ] && [ ! -f "$CONFIG_DIR/.noprompt" ]; then
        if confirm "Install 'repodir' as a command in $BIN_DIR?" y; then
            install_system
        else
            mkdir -p "$CONFIG_DIR" && : > "$CONFIG_DIR/.noprompt"
        fi
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
