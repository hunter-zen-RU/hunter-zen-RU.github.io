#!/usr/bin/env bash
#
#   ┌─┐┌─┐┌─┐┬┌─┌─┐┌─┐┬─┐
#   ├─┘├─┤│  ├┴┐└─┐├┤ ├┬┘
#   ┴  ┴ ┴└─┘┴ ┴└─┘└─┘┴└─
#   packser — universal package installer suite for Linux
#
#   • detects distro + package manager (apt dnf yum pacman zypper apk xbps)
#   • diagnoses and repairs a broken package manager
#   • dashboard, category browser, fuzzy search, marking, update/upgrade
#   • native repos + Flatpak (Flathub) + Snap behind one catalog
#   • fzf when available, built-in arrow-key picker otherwise
#
#   Run:      bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/packser/main/packser.sh)
#        or:  curl -fsSL https://raw.githubusercontent.com/YOUR_USER/packser/main/packser.sh | bash
#   License:  MIT
#
# NOTE: the whole program lives in functions and only runs on the very last
# line. That is what makes `curl ... | bash` safe: bash has read the entire
# script before we re-attach stdin to the terminal.

if [ -z "${BASH_VERSION:-}" ]; then
  echo "packser requires bash (on Alpine: apk add bash). Try: curl -fsSL <url> | bash" >&2
  exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "packser requires bash >= 4 (found $BASH_VERSION)" >&2
  exit 1
fi

VERSION="1.0.0"
RAW_URL="${PACKSER_URL:-https://raw.githubusercontent.com/YOUR_USER/packser/main/packser.sh}"
CONF_DIR="${XDG_CONFIG_HOME:-${HOME:-/tmp}/.config}/packser"
CONF_FILE="$CONF_DIR/config"
MARK_FILE="$CONF_DIR/marked"

# ── runtime state ───────────────────────────────────────────────────────────
DRY=0 ASSUME_YES=0 NO_COLOR_FLAG=0 NOFZF_FLAG=0 FZF_MODE=auto PREFER=native
OS_ID=unknown OS_NAME=Linux OS_VER="" OS_LIKE="" OS_PRETTY="Linux" FAMILY=unknown
KERNEL="" ARCH="" ENVTAG="" PM=none PMKEY="" NATIVE_OK=0 IMMUTABLE=0 SUDO=""
UPD_NATIVE="?" HC_OK=0 HC_WARN=0 HC_ERR=0 QUIET=0 DEEP=0
COLS=80 ROWS=24 BW=76 UTF8=0
RST="" BLD="" DIM="" RED="" GRN="" YLW="" BLU="" MAG="" CYN="" REV=""
ANSI_PAT=$'\e'; ANSI_PAT+='\[+([0-9;])m'   # extglob pattern, used at runtime only

declare -a C_CAT=() C_ID=() C_DESC=() C_MAP=() CATS=()
declare -a MARK_ORDER=() FIX_DESC=() FIX_CMD=() P_KEYS=() P_TEXT=() P_OUT=() P_HOT=() ARGS=()
declare -A C_IDX=() CAT_SEEN=() MARK=() INST=()
R_SRC="" R_NAME="" R_FLAG="" K_SRC="" K_NAME="" K_FLAG="" K_LABEL="" MAPV="" CHOICE=""

# ════════════════════════════════════════════════════════════════════════════
#  CATALOG   Category|id|Description|overrides
#  overrides (comma separated):  <pm>=<name[+name2]>  n=<name>  fp=<flathub id>  sn=<snap[:classic]>
#  pm keys: apt dnf pacman zypper apk xbps      "-" means "not available there"
# ════════════════════════════════════════════════════════════════════════════
catalog_data() {
cat <<'EOF'
Essentials|git|Distributed version control|
Essentials|curl|Transfer data with URLs|
Essentials|wget|Network file downloader|
Essentials|vim|Classic modal text editor|dnf=vim-enhanced
Essentials|neovim|Hyperextensible vim fork|
Essentials|nano|Simple, friendly editor|
Essentials|tmux|Terminal multiplexer|
Essentials|htop|Interactive process viewer|
Essentials|btop|Modern resource monitor|
Essentials|tree|Directory listing as a tree|
Essentials|unzip|Extract .zip archives|
Essentials|zip|Create .zip archives|
Essentials|jq|JSON processor|
Essentials|ripgrep|Blazing fast recursive grep|
Essentials|fd|Friendly alternative to find|apt=fd-find,dnf=fd-find
Essentials|fzf|Command-line fuzzy finder|
Essentials|bat|cat clone with syntax highlighting|
Essentials|eza|Modern replacement for ls|
Essentials|rsync|Fast incremental file transfer|
Essentials|ncdu|Disk usage analyzer (ncurses)|
Essentials|fastfetch|System information tool|
Essentials|rclone|Sync files to cloud storage|
Development|build-tools|Compiler toolchain (gcc, make)|apt=build-essential,dnf=gcc+gcc-c+++make+automake,pacman=base-devel,zypper=gcc+gcc-c+++make+automake,apk=build-base,xbps=base-devel
Development|cmake|Cross-platform build system|
Development|gdb|GNU debugger|
Development|valgrind|Memory error detector|
Development|python3|Python interpreter|pacman=python
Development|python3-pip|Python package installer|pacman=python-pip,apk=py3-pip
Development|pipx|Run Python CLI apps in isolation|pacman=python-pipx,zypper=python3-pipx,xbps=-
Development|nodejs|Node.js runtime + npm|apt=nodejs+npm,dnf=nodejs+npm,pacman=nodejs+npm,zypper=nodejs-default+npm-default,apk=nodejs+npm,xbps=nodejs
Development|golang|Go programming language|apt=golang-go,pacman=go,zypper=go,apk=go,xbps=go
Development|rust|Rust compiler + cargo|apt=rustc+cargo,dnf=rust+cargo,zypper=rust+cargo,apk=rust+cargo,xbps=rust+cargo
Development|openjdk|Java development kit|apt=default-jdk,dnf=java-latest-openjdk-devel,pacman=jdk-openjdk,zypper=java-21-openjdk-devel,apk=openjdk21,xbps=openjdk21
Development|gh|GitHub command-line client|pacman=github-cli,apk=github-cli,xbps=github-cli
Development|sqlite|Embedded SQL database|apt=sqlite3,zypper=sqlite3
Development|postgresql|PostgreSQL database server|dnf=postgresql-server,zypper=postgresql-server
Development|mariadb|MariaDB database server|apt=mariadb-server,dnf=mariadb-server
Development|nginx|High-performance web server|
Development|vscode|Visual Studio Code editor|n=-,fp=com.visualstudio.code,sn=code:classic
Development|dbeaver|Universal database GUI|n=-,fp=io.dbeaver.DBeaverCommunity,sn=dbeaver-ce
Development|insomnia|REST / GraphQL API client|n=-,fp=rest.insomnia.Insomnia,sn=insomnia
Shell & Terminal|zsh|Powerful interactive shell|
Shell & Terminal|fish|Friendly interactive shell|
Shell & Terminal|starship|Cross-shell prompt|
Shell & Terminal|zoxide|Smarter cd command|
Shell & Terminal|direnv|Per-directory environments|
Shell & Terminal|kitty|GPU-accelerated terminal|
Shell & Terminal|alacritty|Fast GPU terminal emulator|
Shell & Terminal|wezterm|GPU terminal with multiplexer|n=-,fp=org.wezfurlong.wezterm
Shell & Terminal|bash-completion|Programmable bash completion|
Containers & VMs|docker|Container engine|apt=docker.io,dnf=moby-engine
Containers & VMs|docker-compose|Multi-container orchestration|apk=docker-cli-compose
Containers & VMs|podman|Daemonless container engine|
Containers & VMs|distrobox|Any distro inside your terminal|
Containers & VMs|kubectl|Kubernetes command-line tool|apt=-,dnf=kubernetes-client,zypper=kubernetes-client,sn=kubectl:classic
Containers & VMs|helm|Kubernetes package manager|apt=-,sn=helm:classic
Containers & VMs|ansible|Agentless IT automation|
Containers & VMs|qemu|Machine emulator and virtualizer|apt=qemu-system-x86,dnf=qemu-kvm,pacman=qemu-full,zypper=qemu-x86,apk=qemu-system-x86_64
Containers & VMs|libvirt|Virtualization management daemon|apt=libvirt-daemon-system,apk=libvirt-daemon
Containers & VMs|virt-manager|Desktop VM manager|
Containers & VMs|virtualbox|Oracle VM VirtualBox|dnf=-,apk=-
Networking & Security|openssh|SSH client and server|apt=openssh-server,dnf=openssh-server
Networking & Security|nmap|Network scanner|
Networking & Security|wireshark|Network protocol analyzer|pacman=wireshark-qt,fp=org.wireshark.Wireshark
Networking & Security|tcpdump|Packet capture on the CLI|
Networking & Security|mtr|Traceroute + ping combined|
Networking & Security|traceroute|Print the route packets take|
Networking & Security|dig|DNS lookup utility|apt=dnsutils,dnf=bind-utils,pacman=bind,zypper=bind-utils,apk=bind-tools,xbps=bind-utils
Networking & Security|netcat|TCP/UDP Swiss-army knife|apt=netcat-openbsd,dnf=nmap-ncat,pacman=openbsd-netcat,zypper=netcat-openbsd,apk=netcat-openbsd,xbps=netcat
Networking & Security|iperf3|Network bandwidth tester|
Networking & Security|socat|Multipurpose relay|
Networking & Security|ufw|Uncomplicated firewall|
Networking & Security|fail2ban|Ban abusive hosts|
Networking & Security|wireguard|Modern VPN tunnel tools|apt=wireguard,dnf=wireguard-tools,pacman=wireguard-tools,zypper=wireguard-tools,apk=wireguard-tools,xbps=wireguard-tools
Networking & Security|openvpn|Classic VPN client/server|
Networking & Security|gnupg|OpenPGP encryption|dnf=gnupg2,zypper=gpg2
Networking & Security|clamav|Open-source antivirus|
Networking & Security|keepassxc|Offline password manager|fp=org.keepassxc.KeePassXC
Networking & Security|bitwarden|Password manager desktop app|n=-,fp=com.bitwarden.desktop,sn=bitwarden
Internet & Chat|firefox|Mozilla Firefox browser|fp=org.mozilla.firefox,sn=firefox
Internet & Chat|chromium|Chromium web browser|fp=org.chromium.Chromium,sn=chromium
Internet & Chat|brave|Brave privacy browser|n=-,fp=com.brave.Browser,sn=brave
Internet & Chat|thunderbird|Mozilla Thunderbird mail|zypper=MozillaThunderbird,fp=org.mozilla.Thunderbird
Internet & Chat|telegram|Telegram Desktop|apt=telegram-desktop,dnf=-,pacman=telegram-desktop,zypper=telegram-desktop,apk=telegram-desktop,xbps=telegram-desktop,fp=org.telegram.desktop,sn=telegram-desktop
Internet & Chat|discord|Voice, video and text chat|n=-,fp=com.discordapp.Discord,sn=discord
Internet & Chat|slack|Team messaging|n=-,fp=com.slack.Slack,sn=slack:classic
Internet & Chat|signal|Private messenger|n=-,fp=org.signal.Signal,sn=signal-desktop
Internet & Chat|zoom|Video conferencing|n=-,fp=us.zoom.Zoom
Internet & Chat|weechat|Extensible IRC client|
Internet & Chat|irssi|Terminal IRC client|
Internet & Chat|qbittorrent|BitTorrent client|
Internet & Chat|filezilla|FTP / SFTP client|
Multimedia|vlc|Play almost any media file|dnf=-,zypper=-,fp=org.videolan.VLC,sn=vlc
Multimedia|mpv|Minimalist media player|dnf=-,zypper=-,fp=io.mpv.Mpv
Multimedia|ffmpeg|Audio/video swiss-army knife|dnf=ffmpeg-free,zypper=-
Multimedia|yt-dlp|Download online video/audio|
Multimedia|obs-studio|Streaming and recording|dnf=-,zypper=-,fp=com.obsproject.Studio
Multimedia|audacity|Multi-track audio editor|fp=org.audacityteam.Audacity
Multimedia|kdenlive|Non-linear video editor|fp=org.kde.kdenlive
Multimedia|handbrake|Video transcoder|dnf=-,zypper=-,apk=-,fp=fr.handbrake.ghb
Multimedia|gimp|GNU image manipulation|fp=org.gimp.GIMP
Multimedia|inkscape|Vector graphics editor|fp=org.inkscape.Inkscape
Multimedia|krita|Digital painting|fp=org.kde.krita
Multimedia|blender|3D creation suite|fp=org.blender.Blender
Multimedia|imagemagick|Image conversion toolkit|dnf=ImageMagick,zypper=ImageMagick,xbps=ImageMagick
Multimedia|flameshot|Screenshot tool with annotations|fp=org.flameshot.Flameshot
Multimedia|spotify|Music streaming|n=-,fp=com.spotify.Client,sn=spotify
Office & Reading|libreoffice|Full office suite|pacman=libreoffice-fresh,fp=org.libreoffice.LibreOffice
Office & Reading|onlyoffice|MS Office compatible editors|n=-,fp=org.onlyoffice.desktopeditors,sn=onlyoffice-desktopeditors
Office & Reading|obsidian|Markdown knowledge base|n=-,fp=md.obsidian.Obsidian,sn=obsidian:classic
Office & Reading|joplin|Note-taking with sync|n=-,fp=net.cozic.joplin_desktop,sn=joplin-desktop
Office & Reading|calibre|E-book manager|fp=com.calibre_ebook.calibre
Office & Reading|evince|Simple PDF/document viewer|
Office & Reading|okular|KDE document viewer|
Office & Reading|zathura|Minimal vi-style PDF viewer|
Office & Reading|syncthing|Continuous file synchronization|
Office & Reading|nextcloud-desktop|Nextcloud sync client|dnf=nextcloud-client,pacman=nextcloud-client,apk=nextcloud-client,xbps=nextcloud-client,fp=com.nextcloud.desktopclient.nextcloud
System & Monitoring|glances|Cross-platform system monitor|
System & Monitoring|iotop|Per-process disk I/O|
System & Monitoring|lsof|List open files|
System & Monitoring|strace|Trace system calls|
System & Monitoring|smartmontools|Disk health (SMART)|
System & Monitoring|lm-sensors|Hardware temperature sensors|dnf=lm_sensors,pacman=lm_sensors,zypper=sensors,xbps=lm_sensors
System & Monitoring|inxi|Full system information|
System & Monitoring|pciutils|lspci and friends|
System & Monitoring|usbutils|lsusb and friends|
System & Monitoring|stress-ng|System stress tester|
System & Monitoring|tlp|Laptop power management|
System & Monitoring|gparted|Partition editor|
System & Monitoring|bleachbit|Disk space cleaner|
System & Monitoring|timeshift|System restore snapshots|pacman=-,apk=-
Gaming|steam|Valve's game platform|apt=steam-installer,dnf=-,fp=com.valvesoftware.Steam,sn=steam
Gaming|lutris|Open gaming platform|fp=net.lutris.Lutris
Gaming|wine|Run Windows applications|
Gaming|retroarch|Retro-console emulator frontend|dnf=-,fp=org.libretro.RetroArch
Gaming|gamemode|On-demand game optimisations|
Gaming|mangohud|In-game performance overlay|apk=-
Gaming|heroic|Epic/GOG/Amazon launcher|n=-,fp=com.heroicgameslauncher.hgl
Gaming|prismlauncher|Minecraft launcher|n=-,fp=org.prismlauncher.PrismLauncher
Package Sources|flatpak|Flatpak runtime (Flathub apps)|
Package Sources|snapd|Snap package daemon|pacman=-,zypper=-,apk=-,xbps=-
Fonts|fira-code|Fira Code programming font|apt=fonts-firacode,dnf=fira-code-fonts,pacman=ttf-fira-code,zypper=fira-code-fonts,apk=font-fira-code,xbps=-
Fonts|jetbrains-mono|JetBrains Mono font|apt=fonts-jetbrains-mono,dnf=jetbrains-mono-fonts,pacman=ttf-jetbrains-mono,zypper=jetbrains-mono-fonts,apk=font-jetbrains-mono,xbps=-
EOF
}

# ════════════════════════════════════════════════════════════════════════════
#  UI primitives
# ════════════════════════════════════════════════════════════════════════════
init_ui() {
  [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] && UTF8=1
  if [[ -t 1 && -z ${NO_COLOR:-} && $NO_COLOR_FLAG -eq 0 && ${TERM:-dumb} != dumb ]]; then
    RST=$'\e[0m' BLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GRN=$'\e[32m'
    YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m' REV=$'\e[7m'
  fi
  if (( UTF8 )); then
    S_OK="✔" S_WARN="▲" S_ERR="✖" S_DOT="●" S_RING="○" S_PTR="▶" S_STAR="★" S_ARR="→" S_BUL="◆" S_ELL="…"
    B_TL="╭" B_TR="╮" B_BL="╰" B_BR="╯" B_H="─" B_V="│" B_LT="├" B_RT="┤"
  else
    S_OK="+" S_WARN="!" S_ERR="x" S_DOT="*" S_RING="o" S_PTR=">" S_STAR="*" S_ARR="->" S_BUL="*" S_ELL="~"
    B_TL="+" B_TR="+" B_BL="+" B_BR="+" B_H="-" B_V="|" B_LT="+" B_RT="+"
  fi
  term_size
}

term_size() {
  local s
  if s=$(stty size 2>/dev/null </dev/tty) && [[ -n $s ]]; then ROWS=${s% *}; COLS=${s#* }; fi
  (( COLS < 40 )) && COLS=80
  (( ROWS < 10 )) && ROWS=24
  BW=$(( COLS > 78 ? 76 : COLS - 2 ))
}

have()  { command -v "$1" >/dev/null 2>&1; }
tmo()   { if have timeout; then timeout "$@"; else shift; "$@"; fi; }
info()  { printf '  %s%s%s %s\n' "$BLU" "$S_BUL" "$RST" "$*"; }
ok()    { printf '  %s%s%s %s\n' "$GRN" "$S_OK" "$RST" "$*"; }
warn()  { printf '  %s%s%s %s\n' "$YLW" "$S_WARN" "$RST" "$*" >&2; }
err()   { printf '  %s%s%s %s\n' "$RED" "$S_ERR" "$RST" "$*" >&2; }
step()  { printf '\n%s%s %s%s\n' "$BLD$CYN" "$S_PTR" "$*" "$RST"; }
clear_screen() { [[ -t 1 ]] && printf '\e[H\e[2J\e[3J'; return 0; }
rep()   { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }
cleanup() { printf '\e[?25h' 2>/dev/null; }

pause() { printf '\n  %sPress any key to continue%s%s' "$DIM" "$S_ELL" "$RST"; IFS= read -rsn1 _ || true; echo; }
prompt() { # label varname
  local _v; IFS= read -rep "  $1 ❯ " _v || _v=""; printf -v "$2" '%s' "$_v"; }
confirm() { # message [default y|n]
  (( ASSUME_YES )) && return 0
  local def=${2:-y} ans hint='[Y/n]'
  [[ $def == n ]] && hint='[y/N]'
  printf '  %s%s%s %s ' "$BLD" "$1" "$RST" "$hint"
  IFS= read -rsn1 ans || ans=""
  [[ -z $ans || $ans == $'\n' ]] && ans=$def
  printf '%s\n' "$ans"
  [[ $ans == [Yy] ]]
}

# ── box drawing ─────────────────────────────────────────────────────────────
box_top() { printf '%s%s%s%s%s\n' "$CYN" "$B_TL" "$(rep "$B_H" $((BW-2)))" "$B_TR" "$RST"; }
box_sep() { printf '%s%s%s%s%s\n' "$CYN" "$B_LT" "$(rep "$B_H" $((BW-2)))" "$B_RT" "$RST"; }
box_bot() { printf '%s%s%s%s%s\n' "$CYN" "$B_BL" "$(rep "$B_H" $((BW-2)))" "$B_BR" "$RST"; }
box_row() {
  local t=$1 plain=${1//$ANSI_PAT/} pad
  pad=$(( BW - 4 - ${#plain} )); (( pad < 0 )) && pad=0
  printf '%s%s%s %s%*s %s%s%s\n' "$CYN" "$B_V" "$RST" "$t" "$pad" "" "$CYN" "$B_V" "$RST"
}
kv() { local t; printf -v t '%s%-9s%s %s' "$DIM" "$1" "$RST" "$2"; box_row "$t"; }

# ════════════════════════════════════════════════════════════════════════════
#  System detection
# ════════════════════════════════════════════════════════════════════════════
pm_available() {
  case $1 in
    apt) have apt-get ;; dnf) have dnf ;; yum) have yum ;; pacman) have pacman ;;
    zypper) have zypper ;; apk) have apk ;; xbps) have xbps-install ;; *) return 1 ;;
  esac
}

detect_system() {
  if [[ -r /etc/os-release ]]; then
    eval "$(. /etc/os-release 2>/dev/null
      printf 'OS_ID=%q OS_NAME=%q OS_VER=%q OS_LIKE=%q OS_PRETTY=%q' \
        "${ID:-unknown}" "${NAME:-Linux}" "${VERSION_ID:-}" "${ID_LIKE:-}" "${PRETTY_NAME:-Linux}")"
  fi
  KERNEL=$(uname -r 2>/dev/null) ARCH=$(uname -m 2>/dev/null)

  case " $OS_ID $OS_LIKE " in
    *" debian "*|*" ubuntu "*)                         FAMILY=debian ;;
    *" fedora "*|*" rhel "*|*" centos "*)              FAMILY=redhat ;;
    *" arch "*)                                        FAMILY=arch ;;
    *" suse "*|*" opensuse "*|*" sles "*)              FAMILY=suse ;;
    *" alpine "*)                                      FAMILY=alpine ;;
    *" void "*)                                        FAMILY=void ;;
    *" nixos "*)                                       FAMILY=nix ;;
    *" gentoo "*)                                      FAMILY=gentoo ;;
  esac

  local pref="" c
  case $FAMILY in debian) pref=apt;; redhat) pref=dnf;; arch) pref=pacman;; suse) pref=zypper;; alpine) pref=apk;; void) pref=xbps;; esac
  PM=none
  for c in $pref apt dnf yum pacman zypper apk xbps; do
    [[ -n $c ]] && pm_available "$c" && { PM=$c; break; }
  done
  PMKEY=$PM; [[ $PM == yum ]] && PMKEY=dnf

  [[ -e /run/ostree-booted || -e /etc/NIXOS ]] && IMMUTABLE=1
  (( IMMUTABLE == 0 )) && [[ $PM != none ]] && NATIVE_OK=1

  if grep -qi microsoft /proc/version 2>/dev/null; then ENVTAG="WSL"
  elif [[ -f /.dockerenv ]] || grep -qaE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then ENVTAG="container"
  elif (( IMMUTABLE )); then ENVTAG="immutable"
  fi

  if (( EUID == 0 )); then SUDO=""
  elif have sudo; then SUDO=sudo
  elif have doas; then SUDO=doas
  fi
}

# ════════════════════════════════════════════════════════════════════════════
#  Config + marks
# ════════════════════════════════════════════════════════════════════════════
load_config() {
  [[ -r $CONF_FILE ]] || return 0
  local k v
  while IFS='=' read -r k v; do
    case $k in
      FZF_MODE) [[ $v == auto || $v == builtin ]] && FZF_MODE=$v ;;
      PREFER)   [[ $v == native || $v == flatpak || $v == snap ]] && PREFER=$v ;;
    esac
  done <"$CONF_FILE"
}
save_config() { mkdir -p "$CONF_DIR" && printf 'FZF_MODE=%s\nPREFER=%s\n' "$FZF_MODE" "$PREFER" >"$CONF_FILE"; }

load_marks() {
  MARK=(); MARK_ORDER=()
  [[ -r $MARK_FILE ]] || return 0
  local k
  while IFS= read -r k; do
    [[ -n $k && -z ${MARK[$k]:-} ]] && { MARK[$k]=1; MARK_ORDER+=("$k"); }
  done <"$MARK_FILE"
}
save_marks() { mkdir -p "$CONF_DIR" && printf '%s\n' "${MARK_ORDER[@]}" >"$MARK_FILE"; }
add_mark() { [[ -n ${MARK[$1]:-} ]] && return 0; MARK[$1]=1; MARK_ORDER+=("$1"); save_marks; }
del_mark() {
  [[ -z ${MARK[$1]:-} ]] && return 0
  unset 'MARK[$1]'
  local k new=(); for k in "${MARK_ORDER[@]}"; do [[ $k != "$1" ]] && new+=("$k"); done
  MARK_ORDER=("${new[@]}"); save_marks
}
toggle_mark() { if [[ -n ${MARK[$1]:-} ]]; then del_mark "$1"; else add_mark "$1"; fi; }

# ════════════════════════════════════════════════════════════════════════════
#  Catalog + source resolution
# ════════════════════════════════════════════════════════════════════════════
load_catalog() {
  local cat id desc map
  while IFS='|' read -r cat id desc map; do
    [[ -z $cat || $cat == \#* ]] && continue
    C_CAT+=("$cat"); C_ID+=("$id"); C_DESC+=("$desc"); C_MAP+=("$map")
    C_IDX[$id]=$(( ${#C_ID[@]} - 1 ))
    if [[ -z ${CAT_SEEN[$cat]:-} ]]; then CAT_SEEN[$cat]=1; CATS+=("$cat"); fi
  done < <(catalog_data)
}

map_get() { # map key → MAPV ; status 0 if key present
  MAPV=""
  local kv IFS=','
  for kv in $1; do
    if [[ ${kv%%=*} == "$2" ]]; then MAPV=${kv#*=}; return 0; fi
  done
  return 1
}

resolve() { # catalog id → R_SRC R_NAME R_FLAG ; status 1 if unavailable on this system
  local id=$1 idx=${C_IDX[$1]:-} map nat="" fp="" sn="" o
  R_SRC="" R_NAME="" R_FLAG=""
  [[ -z $idx ]] && return 1
  map=${C_MAP[$idx]}
  if (( NATIVE_OK )); then
    if map_get "$map" "$PMKEY"; then nat=$MAPV
    elif map_get "$map" n; then nat=$MAPV
    else nat=$id; fi
    [[ $nat == "-" ]] && nat=""
  fi
  map_get "$map" fp && fp=$MAPV
  map_get "$map" sn && sn=$MAPV
  [[ -n $sn ]] && ! have snap && sn=""
  [[ -n $fp ]] && ! have flatpak && (( ! NATIVE_OK )) && fp=""
  local -a order=(nat fp sn)
  [[ $PREFER == flatpak ]] && order=(fp nat sn)
  [[ $PREFER == snap ]]    && order=(sn nat fp)
  for o in "${order[@]}"; do
    case $o in
      nat) [[ -n $nat ]] && { R_SRC=$PM; R_NAME=$nat; return 0; } ;;
      fp)  [[ -n $fp  ]] && { R_SRC=flatpak; R_NAME=$fp; return 0; } ;;
      sn)  [[ -n $sn  ]] && { R_SRC=snap; R_NAME=${sn%%:*}; [[ $sn == *:classic ]] && R_FLAG=--classic; return 0; } ;;
    esac
  done
  return 1
}

key_info() { # key → K_SRC K_NAME K_FLAG K_LABEL ; status 1 if unavailable
  local k=$1 rest
  K_SRC="" K_NAME="" K_FLAG="" K_LABEL=${k#@}
  if [[ $k == @* ]]; then
    rest=${k#@}; K_SRC=${rest%%:*}; K_NAME=${rest#*:}; K_LABEL=$K_NAME
    return 0
  fi
  if resolve "$k"; then K_SRC=$R_SRC K_NAME=$R_NAME K_FLAG=$R_FLAG; return 0; fi
  return 1
}

# installed-package cache (assoc "src:name")
load_installed() {
  INST=(); local n
  if (( NATIVE_OK )); then
    case $PM in
      apt)     while read -r n; do INST[apt:$n]=1; done < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1=="ii"{print $2}') ;;
      dnf|yum) while read -r n; do INST[$PM:$n]=1; done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null) ;;
      zypper)  while read -r n; do INST[zypper:$n]=1; done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null) ;;
      pacman)  while read -r n; do INST[pacman:$n]=1; done < <(pacman -Qq 2>/dev/null) ;;
      apk)     while read -r n; do INST[apk:$n]=1; done < <(apk info 2>/dev/null) ;;
      xbps)    while read -r n; do INST[xbps:$n]=1; done < <(xbps-query -l 2>/dev/null | awk '{n=$2; sub(/-[^-]+$/,"",n); print n}') ;;
    esac
  fi
  if have flatpak; then while read -r n; do INST[flatpak:$n]=1; done < <(flatpak list --app --columns=application 2>/dev/null); fi
  if have snap;    then while read -r n; do INST[snap:$n]=1; done < <(snap list 2>/dev/null | awk 'NR>1{print $1}'); fi
}

is_inst() { # src name(+name2)
  local s=$1 p IFS=+
  for p in $2; do [[ -n ${INST[$s:$p]:-} ]] || return 1; done
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
#  Native package-manager adapter
# ════════════════════════════════════════════════════════════════════════════
run() {
  printf '  %s$ %s%s\n' "$DIM" "$*" "$RST"
  (( DRY )) && { printf '  %s(dry-run: not executed)%s\n' "$DIM" "$RST"; return 0; }
  "$@"
}

need_root() {
  (( EUID == 0 || DRY )) && return 0
  if [[ -z $SUDO ]]; then err "Root privileges required, but neither sudo nor doas was found. Re-run as root."; return 1; fi
  if [[ $SUDO == sudo ]]; then sudo -v || { err "sudo authentication failed"; return 1; }; fi
  return 0
}

native_refresh() {
  case $PM in
    apt)    run $SUDO apt-get update ;;
    dnf)    run $SUDO dnf -y makecache --refresh ;;
    yum)    run $SUDO yum -y makecache ;;
    pacman) run $SUDO pacman -Sy ;;
    zypper) run $SUDO zypper --non-interactive refresh ;;
    apk)    run $SUDO apk update ;;
    xbps)   run $SUDO xbps-install -Sy ;;
  esac
}
native_install() {
  case $PM in
    apt)       run $SUDO apt-get install -y "$@" ;;
    dnf|yum)   run $SUDO "$PM" install -y "$@" ;;
    pacman)    run $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper)    run $SUDO zypper --non-interactive install "$@" ;;
    apk)       run $SUDO apk add "$@" ;;
    xbps)      run $SUDO xbps-install -y "$@" ;;
  esac
}
native_remove() {
  case $PM in
    apt)       run $SUDO apt-get remove -y "$@" ;;
    dnf|yum)   run $SUDO "$PM" remove -y "$@" ;;
    pacman)    run $SUDO pacman -Rns --noconfirm "$@" ;;
    zypper)    run $SUDO zypper --non-interactive remove "$@" ;;
    apk)       run $SUDO apk del "$@" ;;
    xbps)      run $SUDO xbps-remove -Ry "$@" ;;
  esac
}
native_upgrade() { # scope: all|native|full
  case $PM in
    apt)     if [[ $1 == full ]]; then run $SUDO apt-get dist-upgrade -y; else run $SUDO apt-get upgrade -y; fi ;;
    dnf)     run $SUDO dnf upgrade -y --refresh ;;
    yum)     run $SUDO yum update -y ;;
    pacman)  run $SUDO pacman -Syu --noconfirm ;;
    zypper)  if [[ $1 == full ]]; then run $SUDO zypper --non-interactive dist-upgrade; else run $SUDO zypper --non-interactive update; fi ;;
    apk)     run $SUDO apk upgrade -U ;;
    xbps)    run $SUDO xbps-install -Syu ;;
  esac
}
native_upgrade_some() {
  case $PM in
    apt)       run $SUDO apt-get install --only-upgrade -y "$@" ;;
    dnf|yum)   run $SUDO "$PM" upgrade -y "$@" ;;
    pacman)    warn "Arch does not support partial upgrades — running a full upgrade instead"; run $SUDO pacman -Syu --noconfirm ;;
    zypper)    run $SUDO zypper --non-interactive update "$@" ;;
    apk)       run $SUDO apk add -u "$@" ;;
    xbps)      run $SUDO xbps-install -yu "$@" ;;
  esac
}
native_cleanup() {
  case $PM in
    apt)     run $SUDO apt-get autoremove -y && run $SUDO apt-get autoclean ;;
    dnf|yum) run $SUDO "$PM" autoremove -y; run $SUDO "$PM" clean packages ;;
    pacman)
      local orphans; orphans=$(pacman -Qdtq 2>/dev/null)
      if [[ -n $orphans ]]; then
        info "Orphaned packages: $(echo "$orphans" | tr '\n' ' ')"
        # shellcheck disable=SC2086
        confirm "Remove orphans?" && run $SUDO pacman -Rns --noconfirm $orphans
      fi
      run $SUDO pacman -Sc --noconfirm ;;
    zypper)  run $SUDO zypper --non-interactive clean --all ;;
    apk)     run $SUDO apk cache clean ;;
    xbps)    run $SUDO xbps-remove -Oo ;;
  esac
}
native_info() {
  case $PM in
    apt)       apt-cache show "$1" 2>/dev/null | head -n 30 ;;
    dnf|yum)   "$PM" info "$1" 2>/dev/null ;;
    pacman)    pacman -Si "$1" 2>/dev/null || pacman -Qi "$1" ;;
    zypper)    zypper info "$1" 2>/dev/null ;;
    apk)       apk info -a "$1" 2>/dev/null ;;
    xbps)      xbps-query -R "$1" 2>/dev/null ;;
  esac
}

# "name<TAB>info" lines
native_updates() {
  case $PM in
    apt)     tmo 20 apt list --upgradable 2>/dev/null | awk '/upgradable/{split($1,a,"/"); old=$NF; sub(/\]/,"",old); print a[1]"\t"old" → "$2}' ;;
    dnf|yum) tmo 30 "$PM" -C -q check-update 2>/dev/null | awk 'NF>=3 && $1 ~ /\./ && $1 !~ /^(Obsoleting|Security:)/ {n=$1; sub(/\.[^.]+$/,"",n); print n"\t"$2}' ;;
    pacman)  { tmo 30 checkupdates 2>/dev/null || tmo 20 pacman -Qu 2>/dev/null; } | awk 'NF>=4{print $1"\t"$2" → "$4}' ;;
    zypper)  tmo 30 zypper -q list-updates 2>/dev/null | awk -F'|' 'NF>=5 && $1 ~ /v/ {for(i=3;i<=5;i++) gsub(/ /,"",$i); print $3"\t"$4" → "$5}' ;;
    apk)     tmo 20 apk version -l '<' 2>/dev/null | awk 'NR>1 && $2=="<"{n=$1; sub(/-[0-9][^ ]*$/,"",n); print n"\t"$1" → "$3}' ;;
    xbps)    tmo 20 xbps-install -un 2>/dev/null | awk '$2=="update"{n=$1; sub(/-[^-]+$/,"",n); print n"\t"$1}' ;;
  esac
}
native_installed_list() {
  case $PM in
    apt)       dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\t${Version}\n' 2>/dev/null | awk -F'\t' '$1 ~ /^ii/{print $2"\t"$3}' ;;
    dnf|yum|zypper) rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null | sort ;;
    pacman)    pacman -Q 2>/dev/null | awk '{print $1"\t"$2}' ;;
    apk)       apk info -v 2>/dev/null | awk '{n=$0; sub(/-[0-9][^-]*(-r[0-9]+)?$/,"",n); print n"\t"substr($0,length(n)+2)}' ;;
    xbps)      xbps-query -l 2>/dev/null | awk '{n=$2; sub(/-[^-]+$/,"",n); print n"\t"substr($2,length(n)+2)}' ;;
  esac
}
native_search() { # query → "name<TAB>description"
  local q=$1
  case $PM in
    apt)     apt-cache search "$q" 2>/dev/null | sed 's/ - /\t/' ;;
    dnf)     dnf repoquery -q --qf '%{name}\t%{summary}\n' "*$q*" 2>/dev/null | grep . | sort -u ;;
    yum)     yum -q search "$q" 2>/dev/null | awk -F' : ' '/ : /{n=$1; sub(/\.[^.]+$/,"",n); print n"\t"$2}' ;;
    pacman)  pacman -Ss "$q" 2>/dev/null | awk '/^[^ ]/{split($1,a,"/"); n=a[2]; next} {sub(/^ +/,""); print n"\t"$0}' ;;
    zypper)  zypper -q search "$q" 2>/dev/null | awk -F'|' 'NF>=4 && $2 !~ /Name/ {gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3); print $2"\t"$3}' ;;
    apk)     apk search -v -d "$q" 2>/dev/null | awk '{n=$1; sub(/-[0-9][^ ]*$/,"",n); d=$0; sub(/^[^ ]+ - /,"",d); print n"\t"d}' ;;
    xbps)    xbps-query -Rs "$q" 2>/dev/null | awk '{n=$2; sub(/-[^-]+$/,"",n); $1=""; $2=""; sub(/^ +/,""); print n"\t"$0}' ;;
  esac
}

# ── flatpak / snap helpers ──────────────────────────────────────────────────
ensure_flatpak() {
  if ! have flatpak; then
    (( NATIVE_OK )) || { err "flatpak is missing and there is no native package manager to install it"; return 1; }
    info "Installing the flatpak runtime first"
    native_install flatpak || return 1
  fi
  if ! flatpak remotes 2>/dev/null | grep -q flathub; then
    info "Adding the Flathub remote"
    if (( EUID == 0 )); then run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    else run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; fi
  fi
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
#  Pickers  (fzf if available, built-in arrow-key picker otherwise)
#  in:  P_KEYS[] P_TEXT[]  (P_HOT[] = optional hotkeys)    out: P_OUT[]
# ════════════════════════════════════════════════════════════════════════════
use_fzf() { [[ $FZF_MODE == auto ]] && have fzf; }

picker() { # multi(0|1) title [fzf-height]
  local rc
  if (( ${#P_KEYS[@]} == 0 )); then warn "Nothing to show"; P_HOT=(); return 1; fi
  if use_fzf; then picker_fzf "$1" "$2" "${3:-80%}"; else picker_builtin "$1" "$2"; fi
  rc=$?; P_HOT=(); return $rc
}

picker_fzf() {
  local multi=$1 title=$2 h=$3 i out line hint
  hint="↑↓ move · Enter select · type to filter · Esc back"
  (( multi )) && hint="Tab mark/unmark · Ctrl-A all · Enter confirm · type to filter · Esc back"
  (( UTF8 )) || hint=${hint//·/|}
  local -a args=(--ansi --layout=reverse "--height=$h" --border --info=inline
                 "--prompt=  $title > " --delimiter=$'\t' --with-nth=2.. "--header=$hint")
  (( multi )) && args+=(--multi --bind=ctrl-a:select-all)
  out=$(for i in "${!P_KEYS[@]}"; do printf '%s\t%s\n' "${P_KEYS[i]}" "${P_TEXT[i]}"; done | fzf "${args[@]}") || return 1
  P_OUT=()
  while IFS= read -r line; do [[ -n $line ]] && P_OUT+=("${line%%$'\t'*}"); done <<<"$out"
  (( ${#P_OUT[@]} > 0 ))
}

# helpers below rely on picker_builtin's local variables (dynamic scope)
_pk_refilter() {
  idx=(); local lf=${filt,,} i
  for (( i = 0; i < n; i++ )); do
    if [[ -z $lf || ${plain[i],,} == *"$lf"* ]]; then idx+=("$i"); fi
  done
  cur=0; top=0
}
_pk_clear() { printf '\e[%dA\e[J\e[?25h' "$(( H + 2 ))"; }
_pk_draw() {
  local cnt=${#idx[@]} r k i line mark txt w=$(( COLS - 8 ))
  if (( first )); then first=0; else printf '\e[%dA' "$(( H + 2 + extra ))"; fi
  extra=0
  (( cur >= cnt )) && cur=$(( cnt > 0 ? cnt - 1 : 0 ))
  (( cur < top )) && top=$cur
  (( cur >= top + H )) && top=$(( cur - H + 1 ))
  printf '\e[?25l\r  %s%s%s %s(%d/%d)%s%s\e[K\n' "$BLD$CYN" "$title" "$RST" "$DIM" "$cnt" "$n" "$RST" "${filt:+  ${YLW}filter: ${filt}${RST}}"
  printf '\r  %s%s%s\e[K\n' "$DIM" "$hint" "$RST"
  for (( r = 0; r < H; r++ )); do
    k=$(( top + r ))
    if (( k < cnt )); then
      i=${idx[k]}; mark=""
      if (( multi )); then if [[ -n ${selx[$i]:-} ]]; then mark="[x] "; else mark="[ ] "; fi; fi
      txt=${plain[i]}
      if (( k == cur )); then
        line="${mark}${txt}"
        (( ${#line} > w )) && line="${line:0:w-1}${S_ELL}"
        printf -v line '%-*s' "$w" "$line"
        printf '\r %s%s %s%s\e[K\n' "$BLD$REV" "$S_PTR" "$line" "$RST"
      elif (( ${#txt} + ${#mark} > w )); then
        txt="${mark}${txt}"; printf '\r   %s\e[K\n' "${txt:0:w-1}${S_ELL}"
      else
        printf '\r   %s%s\e[K\n' "$mark" "${P_TEXT[i]}"
      fi
    else
      printf '\r\e[K\n'
    fi
  done
  printf '\e[J'
}

picker_builtin() {
  local multi=$1 title=$2
  local n=${#P_KEYS[@]} H i r key rest cur=0 top=0 filt="" first=1 extra=0 cnt hint
  local -a idx=() plain=()
  local -A selx=()
  for (( i = 0; i < n; i++ )); do plain[i]=${P_TEXT[i]//$ANSI_PAT/}; done
  H=$(( ROWS - 5 )); (( H > 22 )) && H=22; (( H > n )) && H=$n; (( H < 1 )) && H=1
  if (( ${#P_HOT[@]} )); then hint="↑↓ move · Enter select · hotkeys at left · Esc quit"
  elif (( multi )); then hint="↑↓ move · Tab mark · ^A all · Enter confirm · type to filter · Esc back"
  else hint="↑↓ move · Enter select · type to filter · Esc back"; fi
  (( UTF8 )) || hint=${hint//·/|}
  _pk_refilter
  while :; do
    cnt=${#idx[@]}
    _pk_draw
    IFS= read -rsn1 key || { _pk_clear; return 1; }
    if (( ${#P_HOT[@]} )) && [[ -n $key && $key != $'\e' ]]; then
      for (( i = 0; i < ${#P_HOT[@]}; i++ )); do
        if [[ $key == "${P_HOT[i]}" ]]; then cur=$i; key=""; break; fi
      done
    fi
    case $key in
      $'\e')
        rest=""; read -rsn2 -t 0.05 rest || true
        case $rest in
          '[A'|'OA') if (( cur > 0 )); then (( cur-- )); else cur=$(( cnt - 1 )); fi ;;
          '[B'|'OB') if (( cur < cnt - 1 )); then (( cur++ )); else cur=0; fi ;;
          '[5')      read -rsn1 -t 0.05 _ || true; (( cur -= H )); (( cur < 0 )) && cur=0 ;;
          '[6')      read -rsn1 -t 0.05 _ || true; (( cur += H )); (( cur > cnt - 1 )) && cur=$(( cnt - 1 )) ;;
          '[H'|'OH') cur=0 ;;
          '[F'|'OF') cur=$(( cnt - 1 )) ;;
          '[1'|'[7') read -rsn1 -t 0.05 _ || true; cur=0 ;;
          '[4'|'[8') read -rsn1 -t 0.05 _ || true; cur=$(( cnt - 1 )) ;;
          '')        if [[ -n $filt ]]; then filt=""; _pk_refilter; else _pk_clear; return 1; fi ;;
        esac ;;
      '')  # Enter
        (( cnt )) || continue
        P_OUT=()
        if (( multi )); then
          for (( r = 0; r < n; r++ )); do [[ -n ${selx[$r]:-} ]] && P_OUT+=("${P_KEYS[r]}"); done
          (( ${#P_OUT[@]} )) || P_OUT=("${P_KEYS[idx[cur]]}")
        else
          P_OUT=("${P_KEYS[idx[cur]]}")
        fi
        _pk_clear; return 0 ;;
      $'\t') if (( multi && cnt )); then
               i=${idx[cur]}
               if [[ -n ${selx[$i]:-} ]]; then unset 'selx[$i]'; else selx[$i]=1; fi
               (( cur < cnt - 1 )) && (( cur++ ))
             fi ;;
      $'\x01') if (( multi )); then for (( r = 0; r < cnt; r++ )); do selx[${idx[r]}]=1; done; fi ;;
      $'\x15') filt=""; _pk_refilter ;;
      $'\x04') _pk_clear; return 1 ;;
      $'\x7f'|$'\b') if [[ -n $filt ]]; then filt=${filt%?}; _pk_refilter; fi ;;
      *)
        if (( ${#P_HOT[@]} )); then
          case $key in
            j) if (( cur < cnt - 1 )); then (( cur++ )); fi ;;
            k) if (( cur > 0 )); then (( cur-- )); fi ;;
            q) _pk_clear; return 1 ;;
          esac
        elif [[ $key == [[:print:]] ]]; then
          filt+=$key; _pk_refilter
        fi ;;
    esac
  done
}

choose() { # title option...  → CHOICE (1-based) ; status 1 on cancel
  local title=$1 i=1 o; shift
  P_KEYS=(); P_TEXT=(); P_HOT=()
  for o in "$@"; do P_KEYS+=("$i"); P_TEXT+=("$i  $o"); P_HOT+=("$i"); (( i++ )); done
  picker 0 "$title" "$(( $# + 4 ))" || return 1
  CHOICE=${P_OUT[0]}
}

# ════════════════════════════════════════════════════════════════════════════
#  Health checks
# ════════════════════════════════════════════════════════════════════════════
chk() { # status message [fix description] [fix command with literal $SUDO]
  local st=$1 msg=$2 icon
  case $st in
    ok)   (( HC_OK++ ));   icon="${GRN}${S_OK}${RST}" ;;
    warn) (( HC_WARN++ )); icon="${YLW}${S_WARN}${RST}" ;;
    err)  (( HC_ERR++ ));  icon="${RED}${S_ERR}${RST}" ;;
    *)    icon="${BLU}${S_BUL}${RST}" ;;
  esac
  (( QUIET )) || printf '  %s %s\n' "$icon" "$msg"
  if [[ -n ${4:-} ]]; then
    FIX_DESC+=("$3"); FIX_CMD+=("$4")
    (( QUIET )) || printf '      %s%s fix available: %s%s\n' "$DIM" "$S_ARR" "$3" "$RST"
  fi
  return 0
}

doctor() {
  HC_OK=0 HC_WARN=0 HC_ERR=0; FIX_DESC=(); FIX_CMD=()
  chk info "System: $OS_PRETTY · family=$FAMILY · arch=$ARCH${ENVTAG:+ · $ENVTAG}"
  if (( EUID == 0 )); then chk ok "Running as root"
  elif [[ -n $SUDO ]]; then chk ok "Privilege escalation via $SUDO"
  else chk err "Not root and no sudo/doas found — installs will fail"; fi

  if [[ $PM == none ]]; then
    if (( IMMUTABLE )); then chk warn "Immutable OS: native installs disabled — use Flatpak (or rpm-ostree / nix)"
    else chk err "No supported package manager found (apt dnf yum pacman zypper apk xbps)"; fi
  else
    if (( IMMUTABLE )); then chk warn "Immutable OS detected — native package manager ($PM) is bypassed, using Flatpak"
    else chk ok "Package manager: $PM ($(command -v "$([[ $PM == apt ]] && echo apt-get || { [[ $PM == xbps ]] && echo xbps-install || echo "$PM"; })"))"; fi
  fi

  local free
  free=$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')
  if [[ -n $free ]]; then
    if (( free < 300 )); then chk err "Only ${free} MB free on / — installs will likely fail"
    elif (( free < 1000 )); then chk warn "Low disk space on /: ${free} MB free"
    else chk ok "Disk space on /: $(( free / 1024 )) GB free"; fi
  fi

  (( NATIVE_OK )) && case $PM in
    apt) doctor_apt ;; dnf|yum) doctor_rpm ;; pacman) doctor_pacman ;;
    zypper) doctor_zypper ;; apk) doctor_apk ;; xbps) doctor_xbps ;;
  esac

  if have flatpak; then
    if flatpak remotes 2>/dev/null | grep -q .; then chk ok "Flatpak remotes configured"
    else chk warn "Flatpak has no remotes" "Add the Flathub remote" '$SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'; fi
  fi
  if have snap && have systemctl; then
    if systemctl is-active --quiet snapd 2>/dev/null; then chk ok "snapd is running"
    else chk warn "snap is installed but snapd is not active" "Enable snapd" '$SUDO systemctl enable --now snapd.socket'; fi
  fi
  (( DEEP )) && doctor_network
  return 0
}

doctor_network() {
  if getent hosts example.com >/dev/null 2>&1; then chk ok "DNS resolution works"
  else chk err "DNS resolution failed — check /etc/resolv.conf or your connection"; fi
  if have curl; then
    if curl -fsS -m 8 -o /dev/null https://example.com 2>/dev/null; then chk ok "HTTPS connectivity works"
    else chk err "HTTPS request failed — network, proxy or CA-certificate problem"; fi
  elif have wget; then
    if wget -q -T 8 --spider https://example.com 2>/dev/null; then chk ok "HTTPS connectivity works"
    else chk err "HTTPS request failed — network, proxy or CA-certificate problem"; fi
  fi
}

doctor_apt() {
  if have fuser && fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; then
    chk err "dpkg/apt lock is held by another process — wait for it (or check unattended-upgrades)"
  elif pgrep -x 'apt|apt-get|aptitude|dpkg|unattended-upgr' >/dev/null 2>&1; then
    chk warn "An apt/dpkg process is running; installs may block until it finishes"
  else chk ok "No apt/dpkg lock contention"; fi

  if [[ -n $(dpkg --audit 2>/dev/null) || -n $(ls -A /var/lib/dpkg/updates 2>/dev/null) ]]; then
    chk err "dpkg was interrupted (half-configured or unpacked packages)" "Finish configuring packages (dpkg --configure -a)" '$SUDO dpkg --configure -a'
  else chk ok "dpkg database is consistent"; fi

  if apt-get check >/dev/null 2>&1; then chk ok "No broken dependencies"
  else chk err "Broken dependencies detected" "Repair dependencies (apt-get install -f)" '$SUDO apt-get install -f -y'; fi

  local held; held=$(apt-mark showhold 2>/dev/null | wc -l)
  (( held > 0 )) && chk warn "$held package(s) on hold (apt-mark showhold)"

  if ! grep -rEqs '^(deb |Types:)' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    chk err "No apt sources configured in /etc/apt"
  else
    local stamp=/var/lib/apt/periodic/update-success-stamp age
    [[ -e $stamp ]] || stamp=$(ls -dt /var/lib/apt/lists/* 2>/dev/null | head -n1)
    if [[ -n $stamp && -e $stamp ]]; then
      age=$(( ( $(date +%s) - $(stat -c %Y "$stamp") ) / 86400 ))
      if (( age > 14 )); then chk warn "Package lists last refreshed ${age} days ago" "Refresh package lists" '$SUDO apt-get update'
      else chk ok "Package lists refreshed ${age} day(s) ago"; fi
    else chk warn "Package lists have never been fetched" "Refresh package lists" '$SUDO apt-get update'; fi
  fi
}

doctor_rpm() {
  if pgrep -x 'dnf|dnf5|yum|rpm|packagekitd' >/dev/null 2>&1; then
    chk warn "A dnf/yum/rpm/PackageKit process is running; installs may wait for its lock"
  else chk ok "No rpm/dnf lock contention"; fi
  if rpm -qa --qf '' >/dev/null 2>&1; then chk ok "RPM database is readable"
  else chk err "RPM database is damaged" "Rebuild the RPM database" '$SUDO rpm --rebuilddb'; fi
  if ls /etc/yum.repos.d/*.repo >/dev/null 2>&1; then chk ok "Repositories configured in /etc/yum.repos.d"
  else chk warn "No .repo files in /etc/yum.repos.d"; fi
  (( DEEP )) && { if tmo 120 "$PM" check >/dev/null 2>&1; then chk ok "$PM check: no dependency problems"
                  else chk warn "$PM check reported problems (run: $PM check)"; fi; }
}

doctor_pacman() {
  if [[ -e /var/lib/pacman/db.lck ]]; then
    if pgrep -x pacman >/dev/null 2>&1; then chk err "pacman is running and holds the database lock"
    else chk err "Stale pacman lock file (no pacman process running)" "Remove /var/lib/pacman/db.lck" '$SUDO rm -f /var/lib/pacman/db.lck'; fi
  else chk ok "No pacman lock"; fi
  if [[ $(grep -c '^Server' /etc/pacman.d/mirrorlist 2>/dev/null) -gt 0 ]]; then chk ok "Mirrorlist has active mirrors"
  else chk err "No active mirrors in /etc/pacman.d/mirrorlist" "Uncomment mirrors (edit manually; reflector can generate a list)"; fi
  if [[ -d /etc/pacman.d/gnupg ]]; then chk ok "pacman keyring initialised"
  else chk err "pacman keyring missing" "Initialise and populate the keyring" '$SUDO pacman-key --init && $SUDO pacman-key --populate'; fi
  if pacman -Dk >/dev/null 2>&1; then chk ok "pacman -Dk: dependency database consistent"
  else chk warn "pacman -Dk reported dependency inconsistencies"; fi
  if [[ -n $(find /var/lib/pacman/sync -name '*.db' -mtime +14 2>/dev/null | head -n1) ]]; then
    chk warn "Sync databases are older than 14 days — a full upgrade (-Syu) is recommended before installing"
  fi
}

doctor_zypper() {
  if [[ -e /run/zypp.pid ]] && kill -0 "$(cat /run/zypp.pid 2>/dev/null)" 2>/dev/null; then
    chk err "zypper is locked by PID $(cat /run/zypp.pid) (another zypper/PackageKit session)"
  else chk ok "No zypper lock"; fi
  if ls /etc/zypp/repos.d/*.repo >/dev/null 2>&1; then chk ok "Repositories configured"
  else chk err "No repositories in /etc/zypp/repos.d"; fi
  (( DEEP )) && { if tmo 120 zypper -n verify -D >/dev/null 2>&1; then chk ok "zypper verify: dependencies OK"
                  else chk warn "zypper verify reported problems"; fi; }
}

doctor_apk() {
  if [[ $(grep -vc '^#' /etc/apk/repositories 2>/dev/null) -gt 0 ]]; then chk ok "/etc/apk/repositories configured"
  else chk err "/etc/apk/repositories is empty or missing"; fi
  pgrep -x apk >/dev/null 2>&1 && chk warn "An apk process is already running"
  (( DEEP )) && { if tmo 60 apk fix -s >/dev/null 2>&1; then chk ok "apk fix (simulation) clean"
                  else chk warn "apk fix simulation reported problems"; fi; }
}

doctor_xbps() {
  if ls /etc/xbps.d/*.conf /usr/share/xbps.d/*.conf >/dev/null 2>&1; then chk ok "xbps repository configuration present"
  else chk warn "No xbps.d repository configuration found"; fi
  pgrep -x 'xbps-install|xbps-remove' >/dev/null 2>&1 && chk warn "Another xbps process is running"
  (( DEEP )) && { if tmo 120 xbps-pkgdb -a >/dev/null 2>&1; then chk ok "xbps-pkgdb: all packages consistent"
                  else chk warn "xbps-pkgdb found problems"; fi; }
}

repo_test() {
  need_root || return 1
  step "Testing repositories (refreshing package lists)"
  local out bad
  out=$(native_refresh 2>&1); local rc=$?
  bad=$(printf '%s\n' "$out" | grep -Ei 'NO_PUBKEY|not signed|gpg error|signature|\b404\b|failed to (fetch|download)|could not resolve|cannot|unreachable|timed out|error' | head -n 12)
  if (( rc == 0 )) && [[ -z $bad ]]; then ok "All repositories responded cleanly"
  else
    warn "Repository problems detected:"
    printf '%s\n' "$bad" | sed 's/^/      /'
    printf '\n  %sHints:%s NO_PUBKEY/signature → import the repo key or remove the repo · 404 → repo/release no longer\n  exists (disable it) · resolve/timeout → network or mirror issue.\n' "$BLD" "$RST"
  fi
}

apply_fixes() {
  local i
  P_KEYS=(); P_TEXT=()
  for i in "${!FIX_CMD[@]}"; do P_KEYS+=("$i"); P_TEXT+=("${FIX_DESC[i]}  ${DIM}${FIX_CMD[i]//\$SUDO /}${RST}"); done
  picker 1 "Select fixes to apply" || return 0
  local sel=("${P_OUT[@]}")
  confirm "Run ${#sel[@]} fix(es)?" || return 0
  need_root || return 1
  for i in "${sel[@]}"; do
    step "${FIX_DESC[i]}"
    if (( DRY )); then printf '  %s(dry-run) %s%s\n' "$DIM" "${FIX_CMD[i]}" "$RST"
    else eval "${FIX_CMD[i]}" && ok "done" || err "failed"; fi
  done
}

doctor_screen() {
  clear_screen; step "Health check — package manager diagnostics"; echo
  QUIET=0 DEEP=1; doctor; DEEP=0
  echo
  printf '  %s%d ok · %d warning(s) · %d issue(s)%s\n' "$BLD" "$HC_OK" "$HC_WARN" "$HC_ERR" "$RST"
  if (( ${#FIX_CMD[@]} )); then echo; apply_fixes; fi
  echo; confirm "Also test every repository (refreshes package lists)?" n && repo_test
  QUIET=1 doctor; QUIET=0
  pause
}

# ════════════════════════════════════════════════════════════════════════════
#  Counting / state
# ════════════════════════════════════════════════════════════════════════════
count_updates() {
  if (( NATIVE_OK )); then
    UPD_NATIVE=$(native_updates 2>/dev/null | grep -c . || true)
  else UPD_NATIVE=0; fi
}
refresh_state() { load_installed; count_updates; }

# ════════════════════════════════════════════════════════════════════════════
#  Dashboard
# ════════════════════════════════════════════════════════════════════════════
dashboard() {
  clear_screen
  local t s_nat s_fp s_sn s_fz priv ht upd
  box_top
  if (( UTF8 && ROWS >= 30 )); then
    box_row "${BLD}${CYN}┌─┐┌─┐┌─┐┬┌─┌─┐┌─┐┬─┐${RST}   ${BLD}Package Installer Suite${RST}"
    box_row "${BLD}${CYN}├─┘├─┤│  ├┴┐└─┐├┤ ├┬┘${RST}   ${DIM}one menu · every package source${RST}"
    box_row "${BLD}${CYN}┴  ┴ ┴└─┘┴ ┴└─┘└─┘┴└─${RST}   ${DIM}v${VERSION}${RST}"
  else
    box_row "${BLD}${CYN}${S_BUL} PACKSER${RST}  ${DIM}v${VERSION} · package installer suite${RST}"
  fi
  box_sep
  kv System  "$OS_PRETTY${ENVTAG:+ ($ENVTAG)}"
  kv Kernel  "$KERNEL · $ARCH"
  if (( EUID == 0 )); then priv="root"; elif [[ -n $SUDO ]]; then priv="via $SUDO"; else priv="${RED}none${RST}"; fi
  if (( NATIVE_OK )); then s_nat="${GRN}${S_DOT}${RST}"; else s_nat="${RED}${S_ERR}${RST}"; fi
  if have flatpak; then s_fp="${GRN}${S_DOT}${RST}"; else s_fp="${DIM}${S_RING}${RST}"; fi
  if have snap;    then s_sn="${GRN}${S_DOT}${RST}"; else s_sn="${DIM}${S_RING}${RST}"; fi
  if use_fzf;      then s_fz="fzf";  else s_fz="built-in"; fi
  kv Manager "${BLD}${PM}${RST} $s_nat  ${DIM}·${RST}  flatpak $s_fp  snap $s_sn  ${DIM}·${RST}  priv: $priv"
  ht=""
  (( HC_ERR  )) && ht+="${RED}${S_ERR} ${HC_ERR} issue(s)${RST}  "
  (( HC_WARN )) && ht+="${YLW}${S_WARN} ${HC_WARN} warning(s)${RST}  "
  (( HC_ERR + HC_WARN )) || ht="${GRN}${S_OK} healthy${RST}  "
  (( HC_ERR + HC_WARN )) && ht+="${DIM}(9 = details & repair)${RST}"
  kv Health  "$ht"
  if [[ $UPD_NATIVE == "?" ]]; then upd="—"; else upd="$UPD_NATIVE pending"; fi
  kv Packages "${upd} ${DIM}·${RST} ${YLW}${S_STAR}${RST} ${#MARK_ORDER[@]} marked ${DIM}·${RST} ${#C_ID[@]} in catalog ${DIM}·${RST} picker: $s_fz"
  box_bot
  echo
}

# ════════════════════════════════════════════════════════════════════════════
#  Catalog browsing
# ════════════════════════════════════════════════════════════════════════════
cat_row() { # catalog index → appends P_KEYS/P_TEXT
  local i=$1 id=${C_ID[$1]} mark=" " stat tag t maxd
  if resolve "$id"; then
    if is_inst "$R_SRC" "$R_NAME"; then stat="${GRN}${S_OK}${RST}"; else stat="${DIM}${S_RING}${RST}"; fi
    tag="[$R_SRC]"
  else stat="${RED}${S_ERR}${RST}"; tag="[n/a]"; fi
  [[ -n ${MARK[$id]:-} ]] && mark="${YLW}${S_STAR}${RST}"
  maxd=$(( COLS - 54 )); (( maxd < 12 )) && maxd=12
  printf -v t '%s %s %-20s %s%-*s%s %s%s%s' "$mark" "$stat" "$id" "$DIM" "$maxd" "${C_DESC[i]:0:maxd}" "$RST" "$CYN" "$tag" "$RST"
  P_KEYS+=("$id"); P_TEXT+=("$t")
}

browse_categories() {
  local c i t total inst marked
  while :; do
    P_KEYS=(); P_TEXT=()
    for c in "${CATS[@]}"; do
      total=0 inst=0 marked=0
      for i in "${!C_ID[@]}"; do
        [[ ${C_CAT[i]} == "$c" ]] || continue
        (( total++ ))
        [[ -n ${MARK[${C_ID[i]}]:-} ]] && (( marked++ ))
        resolve "${C_ID[i]}" && is_inst "$R_SRC" "$R_NAME" && (( inst++ ))
      done
      printf -v t '%s%-22s%s %s%2d packages · %d installed · %d marked%s' "$BLD" "$c" "$RST" "$DIM" "$total" "$inst" "$marked" "$RST"
      P_KEYS+=("$c"); P_TEXT+=("$t")
    done
    picker 0 "Categories" || return 0
    browse_category "${P_OUT[0]}"
  done
}

browse_category() {
  local cat=$1 i k bad
  while :; do
    P_KEYS=(); P_TEXT=()
    for i in "${!C_ID[@]}"; do [[ ${C_CAT[i]} == "$cat" ]] && cat_row "$i"; done
    picker 1 "$cat  ${DIM}(${S_STAR} marked · ${S_OK} installed · ${S_ERR} n/a)${RST}" || return 0
    bad=0
    for k in "${P_OUT[@]}"; do
      if [[ -z ${MARK[$k]:-} ]] && ! resolve "$k"; then warn "$k is not available for $OS_NAME ($PM) — skipped"; bad=1; continue; fi
      toggle_mark "$k"
    done
    (( bad )) && sleep 1.2
  done
}

# ════════════════════════════════════════════════════════════════════════════
#  Search
# ════════════════════════════════════════════════════════════════════════════
search_flow() {
  local q=${1:-} i hit lq n d src t out mark stat k
  local -A seen=()
  if [[ -z $q ]]; then clear_screen; step "Search packages"; echo; prompt "Query (name, keyword or category)" q; fi
  [[ -z $q ]] && return 0
  P_KEYS=(); P_TEXT=(); lq=${q,,}
  for i in "${!C_ID[@]}"; do
    hit="${C_ID[i]} ${C_DESC[i]} ${C_CAT[i]}"
    if [[ ${hit,,} == *"$lq"* ]]; then
      cat_row "$i"
      resolve "${C_ID[i]}" && seen[$R_SRC:$R_NAME]=1
    fi
  done
  local ncat=${#P_KEYS[@]}
  info "Searching repositories for '$q'…"
  local -a sources=()
  (( NATIVE_OK )) && sources+=("$PM")
  have flatpak && sources+=(flatpak)
  have snap && sources+=(snap)
  for src in "${sources[@]}"; do
    case $src in
      flatpak) out=$(flatpak search --columns=application,name,description "$q" 2>/dev/null | awk -F'\t' 'NF>=2 && $1!="Application ID"{print $1"\t"$2" — "$3}' | head -n 150) ;;
      snap)    out=$(snap find "$q" 2>/dev/null | awk 'NR>1{n=$1; $1=$2=$3=$4=""; sub(/^ +/,""); print n"\t"$0}' | head -n 100) ;;
      *)       out=$(native_search "$q" | head -n 300) ;;
    esac
    while IFS=$'\t' read -r n d; do
      [[ -z $n || -n ${seen[$src:$n]:-} ]] && continue
      k="@$src:$n"
      if is_inst "$src" "$n"; then stat="${GRN}${S_OK}${RST}"; else stat="${DIM}${S_RING}${RST}"; fi
      if [[ -n ${MARK[$k]:-} ]]; then mark="${YLW}${S_STAR}${RST}"; else mark=" "; fi
      local maxd=$(( COLS - 62 )); (( maxd < 12 )) && maxd=12
      printf -v t '%s %s %-30.30s %s%-*s%s %s[%s]%s' "$mark" "$stat" "$n" "$DIM" "$maxd" "${d:0:maxd}" "$RST" "$CYN" "$src" "$RST"
      P_KEYS+=("$k"); P_TEXT+=("$t")
    done <<<"$out"
  done
  if (( ${#P_KEYS[@]} == 0 )); then warn "No results for '$q'"; pause; return 0; fi
  info "${#P_KEYS[@]} result(s) — ${ncat} from the curated catalog"
  have flatpak || info "Tip: install flatpak (Package Sources) to also search Flathub"
  picker 1 "Search: $q" || return 0
  local sel=("${P_OUT[@]}")
  choose "${#sel[@]} selected" "Mark for later install" "Install now" "Cancel" || return 0
  case $CHOICE in
    1) for k in "${sel[@]}"; do add_mark "$k"; done; ok "Marked ${#sel[@]} package(s)"; sleep 1 ;;
    2) install_keys "${sel[@]}"; pause ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
#  Install / remove / upgrade
# ════════════════════════════════════════════════════════════════════════════
install_keys() {
  local -a keys=("$@") todo=() nat=() fpn=() snn=() snf=() skipped=() missing=() good=() bad=() _p=()
  local k p
  (( ${#keys[@]} )) || { warn "Nothing to install"; return 0; }
  for k in "${keys[@]}"; do
    if ! key_info "$k"; then missing+=("$K_LABEL"); continue; fi
    if is_inst "$K_SRC" "$K_NAME"; then skipped+=("$K_LABEL"); (( DRY )) || del_mark "$k"; continue; fi
    todo+=("$k")
    case $K_SRC in
      flatpak) fpn+=("$K_NAME") ;;
      snap)    snn+=("$K_NAME"); snf+=("$K_FLAG") ;;
      *)       IFS=+ read -ra _p <<<"$K_NAME"; nat+=("${_p[@]}") ;;
    esac
  done

  step "Installation plan"
  (( ${#nat[@]} ))     && printf '   %s%-8s%s %s\n' "$CYN" "$PM" "$RST" "${nat[*]}"
  (( ${#fpn[@]} ))     && printf '   %s%-8s%s %s\n' "$CYN" flatpak "$RST" "${fpn[*]}"
  (( ${#snn[@]} ))     && printf '   %s%-8s%s %s\n' "$CYN" snap "$RST" "${snn[*]}"
  (( ${#skipped[@]} )) && printf '   %salready installed: %s%s\n' "$DIM" "${skipped[*]}" "$RST"
  (( ${#missing[@]} )) && printf '   %s%s not available on this system: %s%s\n' "$YLW" "$S_WARN" "${missing[*]}" "$RST"
  (( ${#todo[@]} )) || { echo; return 0; }
  echo
  confirm "Install ${#todo[@]} package(s)?" || return 1
  need_root || return 1

  if (( ${#nat[@]} )); then
    step "Installing via $PM"
    if ! native_install "${nat[@]}"; then
      warn "Batch install failed — retrying one by one to isolate the problem"
      for p in "${nat[@]}"; do native_install "$p" || true; done
    fi
  fi
  if (( ${#fpn[@]} )); then
    step "Installing via Flatpak (Flathub)"
    ensure_flatpak && { run flatpak install -y --noninteractive flathub "${fpn[@]}" || true; }
  fi
  if (( ${#snn[@]} )); then
    step "Installing via Snap"
    for k in "${!snn[@]}"; do run $SUDO snap install "${snn[k]}" ${snf[k]:+"${snf[k]}"} || true; done
  fi

  if (( DRY )); then echo; info "Dry run finished — nothing was changed"; return 0; fi
  load_installed
  for k in "${todo[@]}"; do
    key_info "$k"
    if is_inst "$K_SRC" "$K_NAME"; then good+=("$K_LABEL"); del_mark "$k"; else bad+=("$K_LABEL"); fi
  done
  step "Result"
  (( ${#good[@]} )) && ok "Installed: ${good[*]}"
  (( ${#bad[@]} ))  && { err "Failed: ${bad[*]}"; info "Failed packages stay marked so you can retry. Run the health check (9) if the package manager seems broken."; }
  count_updates
  (( ${#bad[@]} == 0 ))
}

remove_keys() {
  local -a nat=() fpn=() snn=() todo=()
  local k
  for k in "$@"; do
    key_info "$k" || continue
    is_inst "$K_SRC" "$K_NAME" || { warn "$K_LABEL is not installed"; continue; }
    todo+=("$k")
    case $K_SRC in flatpak) fpn+=("$K_NAME");; snap) snn+=("$K_NAME");; *) nat+=("$K_NAME");; esac
  done
  (( ${#todo[@]} )) || return 0
  step "Removal plan"
  (( ${#nat[@]} )) && printf '   %s%-8s%s %s\n' "$CYN" "$PM" "$RST" "${nat[*]}"
  (( ${#fpn[@]} )) && printf '   %s%-8s%s %s\n' "$CYN" flatpak "$RST" "${fpn[*]}"
  (( ${#snn[@]} )) && printf '   %s%-8s%s %s\n' "$CYN" snap "$RST" "${snn[*]}"
  echo
  confirm "Remove ${#todo[@]} package(s)?" n || return 1
  need_root || return 1
  (( ${#nat[@]} )) && native_remove "${nat[@]}"
  (( ${#fpn[@]} )) && run flatpak uninstall -y "${fpn[@]}"
  for k in "${snn[@]}"; do run $SUDO snap remove "$k"; done
  refresh_state
}

do_upgrade() { # all|native|full|flatpak|snap
  local scope=$1
  need_root || return 1
  if [[ $scope == all || $scope == native || $scope == full ]] && (( NATIVE_OK )); then
    step "Upgrading native packages ($PM)"; native_upgrade "$scope"
  fi
  if [[ $scope == all || $scope == flatpak ]] && have flatpak; then step "Upgrading Flatpak apps"; run flatpak update -y; fi
  if [[ $scope == all || $scope == snap ]] && have snap; then step "Refreshing Snap packages"; run $SUDO snap refresh; fi
  (( DRY )) || refresh_state
}

update_lists() {
  need_root || return 1
  if (( NATIVE_OK )); then
    step "Refreshing package lists ($PM)"
    native_refresh
    if [[ $PM == pacman ]]; then
      warn "Arch note: after -Sy, avoid installing single packages without upgrading (partial upgrade)."
      confirm "Run a full system upgrade now?" && native_upgrade all
    fi
  fi
  if have flatpak; then step "Refreshing Flatpak metadata"; run flatpak update --appstream -y; fi
  (( DRY )) || refresh_state
}

upgrade_menu() {
  choose "Upgrade packages" \
    "Everything (native + flatpak + snap)" \
    "Native packages only ($PM)" \
    "Flatpak apps only" \
    "Snap packages only" \
    "Full / distribution upgrade (native, may add/remove packages)" \
    "Back" || return 0
  local scope
  case $CHOICE in 1) scope=all;; 2) scope=native;; 3) scope=flatpak;; 4) scope=snap;; 5) scope=full;; *) return 0;; esac
  clear_screen
  if [[ $scope != flatpak && $scope != snap ]] && (( NATIVE_OK )); then
    confirm "Refresh package lists first?" && { need_root && native_refresh; }
  fi
  confirm "Start upgrade ($scope)?" || return 0
  do_upgrade "$scope"
  pause
}

upgradable_flow() {
  local n v t k src
  clear_screen; step "Checking for upgradable packages"
  P_KEYS=(); P_TEXT=()
  while IFS=$'\t' read -r n v; do
    [[ -z $n ]] && continue
    printf -v t '%s%-9s%s %-34.34s %s%s%s' "$CYN" "[$PM]" "$RST" "$n" "$DIM" "$v" "$RST"
    P_KEYS+=("@$PM:$n"); P_TEXT+=("$t")
  done < <(native_updates)
  if have flatpak; then
    while IFS=$'\t' read -r n v; do
      [[ -z $n ]] && continue
      printf -v t '%s%-9s%s %-34.34s %s%s%s' "$CYN" "[flatpak]" "$RST" "$n" "$DIM" "$v" "$RST"
      P_KEYS+=("@flatpak:$n"); P_TEXT+=("$t")
    done < <(flatpak remote-ls --updates --columns=application,version 2>/dev/null)
  fi
  if have snap; then
    while IFS=$'\t' read -r n v; do
      [[ -z $n ]] && continue
      printf -v t '%s%-9s%s %-34.34s %s%s%s' "$CYN" "[snap]" "$RST" "$n" "$DIM" "$v" "$RST"
      P_KEYS+=("@snap:$n"); P_TEXT+=("$t")
    done < <(snap refresh --list 2>/dev/null | awk 'NR>1{print $1"\t"$2}')
  fi
  if (( ${#P_KEYS[@]} == 0 )); then ok "Everything is up to date (based on the current package lists)"; info "Tip: run 'Update package lists' to fetch fresh metadata"; pause; return 0; fi
  ok "${#P_KEYS[@]} upgrade(s) available — pick packages to upgrade now (Esc to go back)"
  picker 1 "Upgradable packages" || return 0
  local -a nat=() fpn=() snn=()
  for k in "${P_OUT[@]}"; do
    key_info "$k"; src=$K_SRC
    case $src in flatpak) fpn+=("$K_NAME");; snap) snn+=("$K_NAME");; *) nat+=("$K_NAME");; esac
  done
  confirm "Upgrade ${#P_OUT[@]} selected package(s)?" || return 0
  need_root || return 1
  (( ${#nat[@]} )) && native_upgrade_some "${nat[@]}"
  (( ${#fpn[@]} )) && run flatpak update -y "${fpn[@]}"
  (( ${#snn[@]} )) && run $SUDO snap refresh "${snn[@]}"
  (( DRY )) || refresh_state
  pause
}

installed_rows() { # populate P_KEYS/P_TEXT with everything installed
  local n v t
  P_KEYS=(); P_TEXT=()
  if (( NATIVE_OK )); then
    while IFS=$'\t' read -r n v; do
      [[ -z $n ]] && continue
      printf -v t '%s%-9s%s %-38.38s %s%s%s' "$CYN" "[$PM]" "$RST" "$n" "$DIM" "$v" "$RST"
      P_KEYS+=("@$PM:$n"); P_TEXT+=("$t")
    done < <(native_installed_list)
  fi
  if have flatpak; then
    while IFS=$'\t' read -r n v; do
      [[ -z $n ]] && continue
      printf -v t '%s%-9s%s %-38.38s %s%s%s' "$CYN" "[flatpak]" "$RST" "$n" "$DIM" "$v" "$RST"
      P_KEYS+=("@flatpak:$n"); P_TEXT+=("$t")
    done < <(flatpak list --app --columns=application,version 2>/dev/null)
  fi
  if have snap; then
    while IFS=$'\t' read -r n v; do
      [[ -z $n ]] && continue
      printf -v t '%s%-9s%s %-38.38s %s%s%s' "$CYN" "[snap]" "$RST" "$n" "$DIM" "$v" "$RST"
      P_KEYS+=("@snap:$n"); P_TEXT+=("$t")
    done < <(snap list 2>/dev/null | awk 'NR>1{print $1"\t"$2}')
  fi
}

show_info() { # key
  key_info "$1" || { err "Unknown package: $1"; return 1; }
  clear_screen; step "$K_LABEL  ${DIM}[$K_SRC]${RST}"; echo
  case $K_SRC in
    flatpak) flatpak remote-info flathub "$K_NAME" 2>/dev/null || flatpak info "$K_NAME" ;;
    snap)    snap info "$K_NAME" ;;
    *)       native_info "${K_NAME%%+*}" ;;
  esac
}

installed_menu() {
  clear_screen; step "Reading installed packages"
  installed_rows
  info "${#P_KEYS[@]} packages — Enter shows details"
  while :; do
    picker 0 "Installed packages" || return 0
    show_info "${P_OUT[0]}" | { if have less; then less -FRX; else cat; fi; }
  done
}

remove_menu() {
  clear_screen; step "Reading installed packages"
  installed_rows
  picker 1 "Remove packages (Tab to mark several)" || return 0
  remove_keys "${P_OUT[@]}"
  pause
}

cleanup_flow() {
  clear_screen; step "Cleanup"
  confirm "Remove unused packages and clear package caches?" || return 0
  need_root || return 1
  (( NATIVE_OK )) && native_cleanup
  have flatpak && run flatpak uninstall --unused -y
  pause
}

marked_menu() {
  local k t
  while :; do
    clear_screen; step "Marked packages (${#MARK_ORDER[@]})"; echo
    if (( ${#MARK_ORDER[@]} == 0 )); then
      info "Nothing marked yet. Mark packages from Browse (Tab) or Search, then install them in one go."
      pause; return 0
    fi
    for k in "${MARK_ORDER[@]}"; do
      if key_info "$k"; then
        if is_inst "$K_SRC" "$K_NAME"; then t="${GRN}${S_OK} installed${RST}"; else t="${DIM}${S_RING} pending${RST}"; fi
        printf '   %s%s%s %-24s %s%s %s:%s%s  %s\n' "$YLW" "$S_STAR" "$RST" "$K_LABEL" "$DIM" "$S_ARR" "$K_SRC" "$K_NAME" "$RST" "$t"
      else
        printf '   %s%s%s %-24s %s%s not available on this system%s\n' "$RED" "$S_ERR" "$RST" "$K_LABEL" "$DIM" "$S_ARR" "$RST"
      fi
    done
    echo
    choose "Marked packages" "Install all marked" "Review / unmark individual packages" "Clear all marks" "Back" || return 0
    case $CHOICE in
      1) install_keys "${MARK_ORDER[@]}"; pause ;;
      2) P_KEYS=(); P_TEXT=()
         for k in "${MARK_ORDER[@]}"; do P_KEYS+=("$k"); P_TEXT+=("${k#@}"); done
         if picker 1 "Select packages to UNMARK"; then for k in "${P_OUT[@]}"; do del_mark "$k"; done; fi ;;
      3) if confirm "Clear all marks?" n; then MARK=(); MARK_ORDER=(); save_marks; fi ;;
      *) return 0 ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════════════
#  Settings / self management
# ════════════════════════════════════════════════════════════════════════════
self_install() {
  local dest=${1:-/usr/local/bin/packser} src=${BASH_SOURCE[0]:-} tmp
  [[ -d $dest ]] && dest="${dest%/}/packser"
  [[ -w $(dirname "$dest") || $EUID -eq 0 ]] || { dest="$HOME/.local/bin/packser"; mkdir -p "$(dirname "$dest")"; warn "No write access to /usr/local/bin — using $dest"; }
  if [[ -f $src && -r $src && $src != /dev/* && $src != /proc/* ]]; then
    run install -m 0755 "$src" "$dest" || return 1
  else
    tmp=$(mktemp) || return 1
    info "Downloading from $RAW_URL"
    if have curl; then curl -fsSL "$RAW_URL" -o "$tmp"; elif have wget; then wget -qO "$tmp" "$RAW_URL"; else err "curl or wget required"; return 1; fi || { err "Download failed"; rm -f "$tmp"; return 1; }
    bash -n "$tmp" || { err "Downloaded file failed syntax check"; rm -f "$tmp"; return 1; }
    run install -m 0755 "$tmp" "$dest"; rm -f "$tmp"
  fi
  ok "Installed to $dest — run: packser"
}

self_update() {
  local tmp target
  target=$(command -v packser 2>/dev/null || true); [[ -z $target ]] && target=${BASH_SOURCE[0]:-}
  [[ -f $target && -w $target ]] || { err "Cannot locate a writable packser to update (use: self-install)"; return 1; }
  tmp=$(mktemp) || return 1
  info "Fetching $RAW_URL"
  if have curl; then curl -fsSL "$RAW_URL" -o "$tmp"; elif have wget; then wget -qO "$tmp" "$RAW_URL"; else err "curl or wget required"; return 1; fi || { err "Download failed"; rm -f "$tmp"; return 1; }
  bash -n "$tmp" && grep -q '^VERSION=' "$tmp" || { err "Downloaded file is not a valid packser script"; rm -f "$tmp"; return 1; }
  install -m 0755 "$tmp" "$target" && ok "Updated $target to $(grep -m1 '^VERSION=' "$tmp" | cut -d'"' -f2)"; rm -f "$tmp"
}

settings_menu() {
  while :; do
    clear_screen; step "Settings"; echo
    local fz_state="not installed"; have fzf && fz_state="installed"
    choose "Settings" \
      "Picker mode: $FZF_MODE  (fzf: $fz_state)  — toggle auto / built-in" \
      "Preferred source for catalog apps: $PREFER  — cycle native / flatpak / snap" \
      "Install fzf (fuzzy picker)" \
      "Install packser system-wide (/usr/local/bin/packser)" \
      "Re-detect system and refresh state" \
      "Back" || return 0
    case $CHOICE in
      1) if [[ $FZF_MODE == auto ]]; then FZF_MODE=builtin; else FZF_MODE=auto; fi; save_config ;;
      2) case $PREFER in native) PREFER=flatpak;; flatpak) PREFER=snap;; *) PREFER=native;; esac; save_config ;;
      3) install_keys fzf; pause ;;
      4) need_root && self_install; pause ;;
      5) detect_system; startup_scan ;;
      *) return 0 ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════════════
#  Main menu
# ════════════════════════════════════════════════════════════════════════════
startup_scan() {
  printf '  %sScanning system%s%s\n' "$DIM" "$S_ELL" "$RST"
  load_installed
  count_updates
  QUIET=1 doctor; QUIET=0
}

menu_main() {
  local t
  while :; do
    dashboard
    P_KEYS=(browse search marked update upgrade outdated installed remove doctor cleanup settings quit)
    P_HOT=(1 2 3 4 5 6 7 8 9 0 s q)
    P_TEXT=(
      "1  Browse categories         packages grouped by purpose"
      "2  Search packages           catalog + every enabled repository"
      "3  Marked packages (${#MARK_ORDER[@]})       review and install your selection"
      "4  Update package lists      refresh repository metadata"
      "5  Upgrade packages          native · flatpak · snap · full"
      "6  Upgradable packages       see what's new, pick what to upgrade"
      "7  Installed packages        browse everything installed"
      "8  Remove packages           uninstall with multi-select"
      "9  Health check & repair     diagnose the package manager"
      "0  Cleanup                   autoremove + clear caches"
      "s  Settings                  picker, preferred source, self-install"
      "q  Quit"
    )
    picker 0 "Main menu" 18 || { clear_screen; return 0; }
    case ${P_OUT[0]} in
      browse)    browse_categories ;;
      search)    search_flow ;;
      marked)    marked_menu ;;
      update)    clear_screen; update_lists; pause ;;
      upgrade)   upgrade_menu ;;
      outdated)  upgradable_flow ;;
      installed) installed_menu ;;
      remove)    remove_menu ;;
      doctor)    doctor_screen ;;
      cleanup)   cleanup_flow ;;
      settings)  settings_menu ;;
      quit)      clear_screen; return 0 ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════════════
#  CLI
# ════════════════════════════════════════════════════════════════════════════
usage() {
cat <<EOF
${BLD}packser${RST} v$VERSION — universal package installer suite

${BLD}USAGE${RST}
  packser [options] [command] [args]

${BLD}COMMANDS${RST}
  (none)                open the interactive dashboard
  install <pkg>...      install catalog ids (e.g. vscode) or raw package names
  remove  <pkg>...      remove packages
  search  [query]       search the catalog and every enabled repository
  info    <pkg>         show package details
  update                refresh package lists
  upgrade [scope]       upgrade packages: all (default) | native | full | flatpak | snap
  outdated              list pending upgrades
  doctor                diagnose (and optionally repair) the package manager
  catalog               print the built-in catalog and what's available here
  self-install [path]   install packser to /usr/local/bin (or ~/.local/bin)
  self-update           download the newest packser from \$PACKSER_URL
  version | help

${BLD}OPTIONS${RST}
  -y, --yes             assume "yes" for every prompt
  -n, --dry-run         print commands without running them
      --no-color        disable colours
      --no-fzf          use the built-in picker even if fzf is installed

${BLD}RUN WITHOUT INSTALLING${RST}
  bash <(curl -fsSL $RAW_URL)
  curl -fsSL $RAW_URL | bash

${BLD}KEYS${RST}  ↑/↓ move · Enter select · Tab mark (multi) · type to filter · Esc back
EOF
}

cmd_catalog() {
  local c i mark stat tag
  for c in "${CATS[@]}"; do
    printf '\n%s%s%s\n' "$BLD$CYN" "$c" "$RST"
    for i in "${!C_ID[@]}"; do
      [[ ${C_CAT[i]} == "$c" ]] || continue
      if resolve "${C_ID[i]}"; then
        if is_inst "$R_SRC" "$R_NAME"; then stat="${GRN}${S_OK}${RST}"; else stat="${DIM}${S_RING}${RST}"; fi
        tag="[$R_SRC]"
      else stat="${RED}${S_ERR}${RST}"; tag="[n/a]"; fi
      printf '  %s %-20s %-38s %s%s%s\n' "$stat" "${C_ID[i]}" "${C_DESC[i]}" "$DIM" "$tag" "$RST"
    done
  done
}

ensure_tty() {
  [[ -t 0 ]] && return 0
  if { true </dev/tty; } 2>/dev/null; then exec </dev/tty; return 0; fi
  return 1
}

to_keys() { # args → KEYS (catalog ids stay ids, anything else is a raw native package)
  KEYS=()
  local a
  for a in "$@"; do
    if [[ -n ${C_IDX[$a]:-} ]]; then KEYS+=("$a")
    elif (( NATIVE_OK )); then KEYS+=("@$PM:$a")
    else err "'$a' is not in the catalog and no native package manager is available"; return 1; fi
  done
}

main() {
  local a
  shopt -s extglob
  for a in "$@"; do
    case $a in
      -y|--yes)      ASSUME_YES=1 ;;
      -n|--dry-run)  DRY=1 ;;
      --no-color)    NO_COLOR_FLAG=1 ;;
      --no-fzf)      NOFZF_FLAG=1 ;;
      -h|--help)     ARGS=(help); break ;;
      -V|--version)  ARGS=(version); break ;;
      *)             ARGS+=("$a") ;;
    esac
  done
  init_ui
  case ${ARGS[0]:-menu} in
    help)    usage; return 0 ;;
    version) echo "packser $VERSION"; return 0 ;;
  esac

  detect_system; load_config; load_catalog; load_marks
  (( NOFZF_FLAG )) && FZF_MODE=builtin
  trap cleanup EXIT
  trap 'cleanup; echo; exit 130' INT TERM

  local cmd=${ARGS[0]:-menu}; ARGS=("${ARGS[@]:1}")
  if [[ $cmd != catalog && $cmd != self-install && $cmd != self-update ]] && ! ensure_tty && (( ! ASSUME_YES )); then
    err "packser needs an interactive terminal (or pass -y)."; return 1
  fi

  case $cmd in
    menu)
      term_size; clear_screen; startup_scan; menu_main ;;
    install)
      (( ${#ARGS[@]} )) || { err "usage: packser install <pkg>..."; return 1; }
      load_installed; to_keys "${ARGS[@]}" || return 1; install_keys "${KEYS[@]}" ;;
    remove)
      (( ${#ARGS[@]} )) || { err "usage: packser remove <pkg>..."; return 1; }
      load_installed; to_keys "${ARGS[@]}" || return 1; remove_keys "${KEYS[@]}" ;;
    search)
      load_installed; search_flow "${ARGS[*]}" ;;
    info)
      (( ${#ARGS[@]} )) || { err "usage: packser info <pkg>"; return 1; }
      to_keys "${ARGS[0]}" || return 1; show_info "${KEYS[0]}" ;;
    update)
      update_lists ;;
    upgrade)
      case ${ARGS[0]:-all} in all|native|full|flatpak|snap) ;; *) err "unknown scope '${ARGS[0]}'"; return 1 ;; esac
      confirm "Upgrade (${ARGS[0]:-all})?" && do_upgrade "${ARGS[0]:-all}" ;;
    outdated)
      step "Pending upgrades"
      native_updates | sed 's/\t/  /;s/^/   /'
      have flatpak && flatpak remote-ls --updates 2>/dev/null | sed 's/^/   [flatpak] /' ;;
    doctor)
      step "Health check"; echo; DEEP=1 doctor
      printf '\n  %s%d ok · %d warning(s) · %d issue(s)%s\n' "$BLD" "$HC_OK" "$HC_WARN" "$HC_ERR" "$RST"
      if (( ${#FIX_CMD[@]} )); then
        if (( ASSUME_YES )); then
          need_root && { for a in "${!FIX_CMD[@]}"; do step "${FIX_DESC[a]}"; if (( DRY )); then echo "  (dry-run) ${FIX_CMD[a]}"; else eval "${FIX_CMD[a]}"; fi; done; }
        else echo; apply_fixes; fi
      fi
      (( HC_ERR == 0 )) ;;
    catalog)
      load_installed; cmd_catalog ;;
    self-install)
      self_install "${ARGS[0]:-}" ;;
    self-update)
      self_update ;;
    *)
      err "unknown command: $cmd"; usage; return 1 ;;
  esac
}

main "$@"; exit $?
