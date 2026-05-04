#!/usr/bin/env bash
#
# MangoWM Fedora 44 Minimal Installation Script
# Run this from the TTY on a fresh Fedora 44 Everything (minimal) install.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/dotfiles"
WALLPAPERS_DIR="${SCRIPT_DIR}/wallpapers"
SDDM_THEME_DIR="${SCRIPT_DIR}/sddm-theme"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

preflight_checks() {
    log_info "Running preflight checks..."

    if [[ "$(id -u)" -eq 0 ]]; then
        log_err "Do not run this script as root. Run as a regular user with sudo access."
        exit 1
    fi

    if ! sudo -n true 2>/dev/null; then
        log_warn "This script requires sudo privileges. You will be prompted for your password."
    fi

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID:-}" != "fedora" ]]; then
            log_err "This script is designed for Fedora. Detected: ${ID:-unknown}"
            exit 1
        fi
        log_ok "Detected Fedora ${VERSION_ID:-unknown}"
    else
        log_err "Cannot detect operating system."
        exit 1
    fi

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_err "Dotfiles directory not found at ${DOTFILES_DIR}"
        log_err "Make sure this script is in the same directory as the 'dotfiles' folder."
        exit 1
    fi

    log_ok "Preflight checks passed."
}

configure_dnf() {
    log_info "Configuring DNF..."

    # Check if already configured
    if grep -q "^installonly_limit=3" /etc/dnf/dnf.conf 2>/dev/null && \
       grep -q "^max_parallel_downloads=15" /etc/dnf/dnf.conf 2>/dev/null && \
       grep -q "^defaultyes=True" /etc/dnf/dnf.conf 2>/dev/null; then
        log_ok "DNF already configured. Skipping."
        return 0
    fi

    sudo cp /etc/dnf/dnf.conf "/etc/dnf/dnf.conf.bak.$(date +%Y%m%d%H%M%S)"

    # Use Python to safely update only the requested keys while preserving existing config
    sudo python3 - <<'PYEOF'
import configparser
import os

conf_path = "/etc/dnf/dnf.conf"

# Read existing config, preserving case
config = configparser.ConfigParser()
config.optionxform = str
config.read(conf_path)

# Ensure [main] section exists
if not config.has_section("main"):
    config.add_section("main")

# Update only the requested settings
updates = {
    "installonly_limit": "3",
    "max_parallel_downloads": "15",
    "defaultyes": "True"
}

for key, value in updates.items():
    config.set("main", key, value)

# Write back
with open(conf_path, "w") as f:
    config.write(f)

PYEOF

    log_ok "DNF configuration updated safely."
}

add_repositories() {
    log_info "Adding third-party repositories..."

    log_info "Installing RPM Fusion (free and non-free)..."
    if rpm -q rpmfusion-free-release &>/dev/null && rpm -q rpmfusion-nonfree-release &>/dev/null; then
        log_ok "RPM Fusion already installed. Skipping."
    else
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    fi

    log_info "Installing Terra repository..."
    if rpm -q terra-release &>/dev/null; then
        log_ok "Terra repository already installed. Skipping."
    else
        sudo dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release -y
    fi

    log_info "Adding TekkRPM repository..."
    if [[ -f /etc/yum.repos.d/tekk.repo ]] || [[ -f /etc/yum.repos.d/tekk-fedora-42.repo ]]; then
        log_ok "TekkRPM repository already configured. Skipping."
    else
        if ! sudo dnf config-manager addrepo --from-repofile="https://forgejo.jtekk.dev/api/packages/TekkRPM/rpm/tekk-fedora-43.repo" -y 2>/dev/null; then
            log_warn "dnf config-manager failed, falling back to curl..."
            sudo curl -fL -o /etc/yum.repos.d/tekk.repo \
                "https://forgejo.jtekk.dev/api/packages/TekkRPM/rpm/tekk-fedora-42.repo"
        fi
    fi

    log_info "Refreshing package cache..."
    sudo dnf check-update || true

    log_ok "Repositories added."
}

install_packages() {
    log_info "Installing system packages (this may take a while)..."

    # Core dependencies
    sudo dnf install -y \
        kernel-devel kernel-headers gcc make dkms acpid \
        libglvnd-glx libglvnd-opengl libglvnd-devel pkgconfig \
        git curl wget rsync xorg-x11-server-Xwayland

    # System tools
    sudo dnf install -y \
        btop eza htop python3-pip pipx timeshift

    # MangoWM / desktop environment packages
    sudo dnf install -y \
        fastfetch fish helix kitty hyprland noctalia-shell neovim \
        qt5ct qt6ct grim slurp bibata-cursor-theme \
        xdg-desktop-portal-wlr goverlay foot \
        google-noto-color-emoji-fonts

    # Applications
    sudo dnf install -y \
        nemo \
        gnome-disk-utility gnome-software pavucontrol helium-browser zoxide \
        ffmpeg

    # Virtualization
    sudo dnf install -y \
        libvirt virt-manager virt-viewer virt-install

    # SDDM and Qt6 support for Pixie theme
    sudo dnf install -y \
        sddm qt6-qtdeclarative qt6-qtsvg qt6-qtquickcontrols2

    log_ok "All packages installed."
}

install_zed() {
    if command -v zed &>/dev/null || [[ -x ~/.local/bin/zed ]]; then
        log_ok "Zed already installed. Skipping."
        return 0
    fi

    log_info "Installing Zed editor..."
    curl -f https://zed.dev/install.sh | sh
    log_ok "Zed installed to ~/.local/bin/zed"
}

install_sddm_pixie() {
    log_info "Installing Pixie SDDM theme from local files..."

    if [[ ! -d "${SDDM_THEME_DIR}/pixie" ]]; then
        log_err "Local SDDM theme not found at ${SDDM_THEME_DIR}/pixie"
        exit 1
    fi

    # Only copy if theme files are missing or different
    if [[ -f /usr/share/sddm/themes/pixie/Main.qml ]] && \
       diff -q "${SDDM_THEME_DIR}/pixie/Main.qml" /usr/share/sddm/themes/pixie/Main.qml &>/dev/null; then
        log_ok "Pixie SDDM theme already installed. Skipping copy."
    else
        sudo mkdir -p /usr/share/sddm/themes/pixie
        sudo cp -r "${SDDM_THEME_DIR}/pixie/"* /usr/share/sddm/themes/pixie/
        log_ok "Pixie SDDM theme copied."
    fi

    log_info "Applying SDDM theme configuration..."
    sudo mkdir -p /etc/sddm.conf.d
    if [[ -f /etc/sddm.conf.d/theme.conf ]] && \
       diff -q "${SDDM_THEME_DIR}/theme.conf" /etc/sddm.conf.d/theme.conf &>/dev/null; then
        log_ok "SDDM theme config already applied. Skipping."
    else
        sudo cp "${SDDM_THEME_DIR}/theme.conf" /etc/sddm.conf.d/theme.conf
        log_ok "SDDM theme config applied."
    fi

    log_info "Enabling SDDM service..."
    if systemctl is-enabled sddm.service &>/dev/null 2>&1; then
        log_ok "SDDM service already enabled. Skipping."
    else
        sudo systemctl enable sddm --force
        log_ok "SDDM service enabled."
    fi

    # Disable any conflicting display managers
    for dm in gdm lightdm lxdm greetd plasmalogin; do
        if systemctl is-enabled "${dm}.service" &>/dev/null 2>&1; then
            log_info "Disabling conflicting display manager: ${dm}"
            sudo systemctl disable "${dm}.service" || true
        fi
    done

    log_ok "SDDM with Pixie theme installed and enabled."
}

copy_dotfiles() {
    log_info "Copying dotfiles to ~/.config/..."

    mkdir -p ~/.config

    local dirs=(
        fastfetch fish gtk-3.0 gtk-4.0 helix kitty mango
        noctalia nvim obs-studio opencode qt5ct qt6ct yazi zed
    )

    for dir in "${dirs[@]}"; do
        local src="${DOTFILES_DIR}/${dir}"
        local dst="${HOME}/.config/${dir}"

        if [[ -d "$src" ]]; then
            rm -rf "$dst"
            cp -r "$src" "$dst"
            log_ok "Copied ${dir}"
        else
            log_warn "Source directory not found: ${src}"
        fi
    done

    log_ok "All dotfiles copied."
}

copy_wallpapers() {
    log_info "Copying wallpapers..."

    if [[ ! -d "$WALLPAPERS_DIR" ]]; then
        log_warn "Wallpapers directory not found at ${WALLPAPERS_DIR}. Skipping."
        return 0
    fi

    local dst="${HOME}/Pictures/Wallpapers"
    mkdir -p "$dst"

    # Use cp -r to copy all files, preserving the directory structure if any
    cp -r "${WALLPAPERS_DIR}"/* "$dst/"

    log_ok "Wallpapers copied to ${dst}"
}

set_shell() {
    log_info "Setting Fish as default shell..."
    if ! command -v fish &>/dev/null; then
        log_warn "Fish shell not found. Skipping."
        return 0
    fi

    local fish_path
    fish_path="$(command -v fish)"
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"

    if [[ "$current_shell" == "$fish_path" ]]; then
        log_ok "Fish is already the default shell. Skipping."
        return 0
    fi

    chsh -s "$fish_path"
    log_ok "Fish set as default shell. Log out and back in for changes to take effect."
}

cleanup() {
    log_info "Cleaning up..."
    sudo dnf autoremove -y
    sudo dnf clean all
    log_ok "Cleanup complete."
}

main() {
    preflight_checks
    configure_dnf
    add_repositories
    install_packages
    install_zed
    install_nvidia
    install_sddm_pixie
    copy_dotfiles
    copy_wallpapers
    set_shell
    cleanup

    echo ""
    log_ok "Installation complete!"
    log_info "Please reboot your system now: sudo reboot"
    echo ""
    log_info "After reboot:"
    log_info "  - SDDM (Pixie theme) will be your login screen"
    log_info "  - Select your MangoWM session and log in"
    log_info "  - NVIDIA drivers should be active (run nvidia-smi to verify)"
}

main "$@"
