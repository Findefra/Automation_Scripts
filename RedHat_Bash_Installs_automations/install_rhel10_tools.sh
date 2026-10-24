#!/bin/bash
# ================================================
# RHEL 10 CLI/TUI Tools Installer + Aliases
# Disk, Cleanup, Monitoring with quick-launch aliases
# Run as root or with sudo
# ================================================

set -e  # Exit on error

echo "=== Updating system and enabling repositories ==="
sudo dnf update -y

# Enable EPEL for RHEL 10
echo "=== Enabling EPEL repository ==="
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm || true
sudo dnf config-manager --set-enabled crb || true

echo "=== Installing Top 5 TUI Disk & File Management Tools ==="
sudo dnf install -y \
    ncdu \
    mc \
    ranger \
    dust \
    nnn

echo "=== Installing 3 Disk Cleanup Tools ==="
sudo dnf install -y dua-cli || echo "dua-cli: may need Cargo"
sudo dnf install -y bleachbit || true
sudo dnf install -y kondo || echo "kondo: may need Cargo"

echo "=== Installing 4 Visual System Monitoring Tools ==="
sudo dnf install -y \
    htop \
    btop \
    glances \
    atop

# Create system-wide aliases (available to all users)
echo "=== Creating quick-launch aliases ==="
cat << 'EOF' | sudo tee /etc/profile.d/rhel10-tools-aliases.sh > /dev/null
# ================================================
# Quick aliases for RHEL 10 CLI Tools
# ================================================

# Disk & File Management
alias du='dust'                    # Beautiful colored tree (overrides default du)
alias ncdu='ncdu -q'               # Quiet mode for cleaner view
alias mc='mc'                      # Dual-pane file manager
alias rng='ranger'                 # Vim-style file manager
alias nnn='nnn -d'                 # With disk usage mode

# Disk Cleanup
alias dua='dua i'                  # Interactive TUI analyzer + delete
alias bb='bleachbit --clean'       # Quick clean (add cleaners after)
alias kondo='kondo'                # Project cleanup with savings report

# System Monitoring & Performance
alias top='htop'                   # Modern colorful replacement
alias btop='btop'                  # Beautiful modern dashboard
alias gl='glances'                 # Full system overview with graphs
alias atop='atop'                  # Advanced performance monitor

# Common shortcuts
alias disk='ncdu /'                # Quick full disk scan
alias mon='btop'                   # Launch best visual monitor
alias clean='bleachbit -l'         # List available cleaners
EOF

sudo chmod +x /etc/profile.d/rhel10-tools-aliases.sh

echo "=== Installation & Aliases complete! ==="
echo ""
echo "=== Quick Start (after new terminal) ==="
echo ""
echo "Disk & File:"
echo "  du /path       # colored tree (dust)"
echo "  ncdu           # interactive disk browser"
echo "  rng            # ranger file manager"
echo "  nnn            # fast file browser"
echo ""
echo "Cleanup:"
echo "  dua            # interactive cleanup"
echo "  bb system.cache # clean with bleachbit"
echo "  kondo .        # project cleanup"
echo ""
echo "Monitoring:"
echo "  top            # htop (colorful)"
echo "  btop           # stunning dashboard"
echo "  gl             # glances overview"
echo "  atop           # detailed monitoring"
echo ""
echo "  disk           # quick full disk scan"
echo "  mon            # launch best visual monitor"
echo ""
echo "Aliases are system-wide (in /etc/profile.d/)."
echo "Open a **new terminal** or run: source /etc/profile.d/rhel10-tools-aliases.sh"
echo "Perfect toolkit for RHEL 10 servers!"
