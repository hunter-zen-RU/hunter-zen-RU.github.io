# packser v1.1

A clean, professional CLI package installer suite for Linux with support for multiple package managers and sources. Enhanced with arrow-key navigation, batch operations, and curated package database.

## Features

- 🔍 **System Detection** - Automatically detects Linux distribution, architecture, and init system
- 📦 **Multi-Package Manager Support** - APT, DNF, YUM, Pacman, Zypper, APK, Portage, XBPS, and more
- 🐋 **Universal Sources** - Snap, Flatpak, Homebrew (Linux), Nix, AppImage
- 🩺 **Health Monitoring** - Detect issues with package managers and show status
- 📊 **Clean Dashboard** - Professional CLI interface with menu-driven navigation
- 📂 **Category Organization** - Packages organized by System, Network, Multimedia, Development, Games, Security, Utils, Education
- 🔎 **Search Function** - Search across all sources with filters (APT, Snap, Flatpak, Pacman)
- 📋 **Package Management** - View installed packages, update lists, upgrade all from all sources
- ✅ **Mark & Apply** - Mark packages for install/remove/update and apply in batch
- 🗄️ **Package Database** - Curated database of popular packages with categories and sources
- ⌨️ **Enhanced Navigation** - fzf/gum support for arrow-key navigation, falls back to whiptail/dialog/numbers
- 🎯 **Source-Aware** - Lists packages from native managers and universal sources grouped by category

## Installation

### Quick Install (one-liner)

```bash
curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash
```

The installer first asks how you want to use packser:

1. **Install** - downloads packser from GitHub Pages, installs it system-wide in
   `/usr/local/share/packser`, links the `packser` command into
   `/usr/local/bin`, then starts it. This mode requires `sudo`.
2. **Live use** - downloads a temporary copy, runs it once, then deletes the
   downloaded files automatically. Nothing is installed.

You can skip the prompt with a flag:

```bash
# Install system-wide
curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash -s -- --install

# Run a temporary live copy
curl -fsSL https://hunter-zen-ru.github.io/scripts/packser/install.sh | bash -s -- --live
```

The GitHub Pages deployment must expose `install.sh`, `packser`, `README.md`,
and `lib/*.sh` under `https://hunter-zen-ru.github.io/scripts/packser/`.

### Manual Installation

```bash
git clone https://github.com/hunter-zen-ru/packser.git
cd packser
chmod +x packser
./packser
```

## Usage

If you used install mode, run:

```bash
packser
```

From a local checkout, run:

```bash
./packser
```

Navigate using the menu options with arrow keys or numbers.

## Requirements

- Bash 4.0+
- `whiptail` or `dialog` for enhanced UI (optional but recommended)
- Root/sudo access for installing/upgrading packages

## Supported Package Managers

| Package Manager | Distributions | Status |
|---|---|---|
| APT | Debian, Ubuntu, Mint | ✓ |
| DNF | Fedora, RHEL, CentOS Stream | ✓ |
| Pacman | Arch Linux, Manjaro | ✓ |
| Zypper | openSUSE | ✓ |
| APK | Alpine Linux | ✓ |
| Portage (emerge) | Gentoo | ✓ |
| XBPS | Void Linux | ✓ |
| Snap | Universal | ✓ |
| Flatpak | Universal | ✓ |
| Homebrew | Universal (Linux) | ✓ |
| Nix | Universal | ✓ |

## Directory Structure

```
packser/
├── packser          # Main executable
├── lib/
│   ├── detect.sh    # System & package manager detection
│   ├── pm.sh        # Package manager operations
│   ├── ui.sh        # User interface & dashboard
│   ├── search.sh    # Search functionality
│   └── utils.sh     # Utility functions
├── data/            # Package database
└── README.md
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Version

1.1
