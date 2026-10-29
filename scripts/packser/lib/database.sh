#!/usr/bin/env bash
# Package database for packser

load_package_db() {
    local db_file="$DATA_DIR/packages.db"
    
    if [ ! -f "$db_file" ]; then
        generate_package_db
    fi
    
    cat "$db_file"
}

generate_package_db() {
    local db_file="$DATA_DIR/packages.db"
    
    cat > "$db_file" << 'EOF'
# packser package database
# Format: name|category|description|sources|tags
firefox|network|Fast, private web browser|apt,snap,flatpak|browser,web,internet
chromium|network|Open source web browser|apt,snap,flatpak|browser,web,internet
thunderbird|network|Email client|apt,snap,flatpak|email,mail
curl|system|Command line tool for transferring data|apt,dnf,pacman,all|cli,network,tool
wget|system|Network downloader|apt,dnf,pacman,all|cli,download,tool
htop|system|Interactive process viewer|apt,dnf,pacman,brew|monitor,system,cli
btop|system|Resource monitor|apt,dnf,pacman,brew|monitor,system,cli
neofetch|system|System information tool|apt,dnf,pacman,all|info,system,cli
tree|system|Directory listing|apt,dnf,pacman,brew|cli,filesystem
ncdu|system|Disk usage analyzer|apt,dnf,pacman,brew|disk,analyzer,cli
rsync|system|File synchronization|apt,dnf,pacman,all|sync,backup,cli
vim|dev|Vi IMproved text editor|apt,dnf,pacman,brew|editor,cli,code
neovim|dev|Hyperextensible Vim-based editor|apt,dnf,pacman,brew,snap|editor,cli,code
git|dev|Distributed version control|apt,dnf,pacman,brew,all|vcs,git,dev
gcc|dev|GNU Compiler Collection|apt,dnf,pacman|compiler,c,dev
g++|dev|GNU C++ compiler|apt,dnf,pacman|compiler,cpp,dev
make|dev|Build automation tool|apt,dnf,pacman,brew|build,dev,tool
cmake|dev|Cross-platform build system|apt,dnf,pacman,brew|build,dev,tool
nodejs|dev|JavaScript runtime|apt,dnf,pacman,brew,snap|js,node,dev
python3|dev|Python programming language|apt,dnf,pacman,brew,all|python,dev,scripting
docker|dev|Container platform|apt,snap|containers,devops
docker.io|dev|Docker engine|apt|containers,devops
code|dev|Visual Studio Code|apt,snap,flatpak|editor,ide,code
vlc|multimedia|Media player|apt,snap,flatpak|video,audio,player
mpv|multimedia|Minimalist media player|apt,dnf,pacman,flatpak|video,audio,player
ffmpeg|multimedia|Multimedia framework|apt,dnf,pacman,brew|codec,video,audio
obs-studio|multimedia|Screen recorder/streamer|apt,snap,flatpak|record,stream,video
audacity|multimedia|Audio editor|apt,snap,flatpak|audio,edit,music
gimp|multimedia|Image editor|apt,snap,flatpak|image,edit,graphics
inkscape|multimedia|Vector graphics editor|apt,snap,flatpak|vector,graphics,design
steam|games|Gaming platform|apt,flatpak|games,platform
lutris|games|Game launcher|apt,flatpak|games,launcher
0ad|games|Real-time strategy game|apt,flatpak|games,strategy
ufw|security|Uncomplicated Firewall|apt,all|firewall,security,network
fail2ban|security|Intrusion prevention|apt,dnf|security,protect
gpg|security|GNU Privacy Guard|apt,dnf,pacman,all|encryption,security
keepassxc|security|Password manager|apt,snap,flatpak|password,security
veracrypt|security|Disk encryption|apt,flatpak|encryption,security
ranger|utils|File manager (TUI)|apt,dnf,pacman,brew|file,manager,tui
tmux|utils|Terminal multiplexer|apt,dnf,pacman,brew|terminal,multiplexer
zip|utils|Compression tool|apt,dnf,pacman,all|archive,compress
unzip|utils|Decompression tool|apt,dnf,pacman,all|archive,decompress
file-roller|utils|Archive manager (GUI)|apt,snap,flatpak|archive,gui
bleachbit|utils|System cleaner|apt,snap,flatpak|clean,system
nmap|network|Network scanner|apt,dnf,pacman,brew|network,scan,security
wireshark|network|Network protocol analyzer|apt,snap,flatpak|network,analyze
transmission|network|BitTorrent client|apt,snap,flatpak|torrent,download
EOF
    
    echo -e "${GREEN}✓${NC} Package database generated"
}

# Search in database
db_search() {
    local term="$1"
    local category="$2"
    local db_file="$DATA_DIR/packages.db"
    
    if [ ! -f "$db_file" ]; then
        generate_package_db
    fi
    
    grep -i "$term" "$db_file" | grep -v "^#" | while IFS='|' read -r name cat desc sources tags; do
        if [ -n "$category" ] && [ "$category" != "all" ]; then
            [ "$cat" = "$category" ] || continue
        fi
        echo "$name|$cat|$desc|$sources|$tags"
    done
}
