#!/usr/bin/env bash
#
# MangoWM Fedora 42 Minimal Installation Script
# Run this from the TTY on a fresh Fedora 42 Everything (minimal) install.
#
# Expected dotfiles layout:
#   ~/dotfiles/.config/<app>/   → stowed to ~/.config/<app>
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDDM_THEME_DIR="${SCRIPT_DIR}/sddm-theme"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

    if [[ ! -d "${SCRIPT_DIR}/.config" ]]; then
        log_err "Expected ${SCRIPT_DIR}/.config/ not found."
        log_err "Dotfiles must use the layout: ~/dotfiles/.config/<app>/"
        exit 1
    fi

    log_ok "Preflight checks passed."
}

configure_dnf() {
    log_info "Configuring DNF..."

    if grep -q "^installonly_limit=3" /etc/dnf/dnf.conf 2>/dev/null && \
       grep -q "^max_parallel_downloads=15" /etc/dnf/dnf.conf 2>/dev/null && \
       grep -q "^defaultyes=True" /etc/dnf/dnf.conf 2>/dev/null; then
        log_ok "DNF already configured. Skipping."
        return 0
    fi

    sudo cp /etc/dnf/dnf.conf "/etc/dnf/dnf.conf.bak.$(date +%Y%m%d%H%M%S)"

    sudo python3 - <<'PYEOF'
import configparser

conf_path = "/etc/dnf/dnf.conf"

config = configparser.ConfigParser()
config.optionxform = str
config.read(conf_path)

if not config.has_section("main"):
    config.add_section("main")

updates = {
    "installonly_limit": "3",
    "max_parallel_downloads": "15",
    "defaultyes": "True"
}

for key, value in updates.items():
    config.set("main", key, value)

with open(conf_path, "w") as f:
    config.write(f)
PYEOF

    log_ok "DNF configuration updated."
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

    log_info "Adding TekkRPM repository (Fedora 42)..."
    if [[ -f /etc/yum.repos.d/tekk-fedora-42.repo ]]; then
        log_ok "TekkRPM repository already configured. Skipping."
    else
        sudo dnf config-manager addrepo \
            --from-repofile="https://forgejo.jtekk.dev/api/packages/TekkRPM/rpm/tekk-fedora-42.repo" -y
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
        git curl wget rsync stow xorg-x11-server-Xwayland

    # System tools
    sudo dnf install -y \
        btop eza htop python3-pip pipx timeshift

    # Audio (PipeWire stack)
    sudo dnf install -y \
        pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack

    # MangoWM / desktop environment
    sudo dnf install -y \
        fastfetch fish helix kitty hyprland noctalia-shell neovim \
        qt5ct qt6ct grim slurp bibata-cursor-theme \
        xdg-desktop-portal-hyprland goverlay foot \
        wl-clipboard mako polkit-gnome \
        google-noto-color-emoji-fonts

    # Applications
    sudo dnf install -y \
        nemo yazi obs-studio \
        gnome-disk-utility gnome-software pavucontrol helium-browser zoxide \
        ffmpeg

    # Virtualization
    sudo dnf group install -y --with-optional virtualization
    sudo dnf install -y \
        edk2-ovmf swtpm swtpm-tools passt

    # Rust toolchain (required for building virt-related tools from source)
    sudo dnf install -y \
        rust cargo systemd-devel

    # SDDM and Qt6 support for Pixie theme
    sudo dnf install -y \
        sddm qt6-qtdeclarative qt6-qtsvg qt6-qtquickcontrols2

    log_ok "All packages installed."
}

install_sddm_pixie() {
    log_info "Installing Pixie SDDM theme from local files..."

    if [[ ! -d "${SDDM_THEME_DIR}/pixie" ]]; then
        log_err "Local SDDM theme not found at ${SDDM_THEME_DIR}/pixie"
        exit 1
    fi

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

    for dm in gdm lightdm lxdm greetd plasmalogin; do
        if systemctl is-enabled "${dm}.service" &>/dev/null 2>&1; then
            log_info "Disabling conflicting display manager: ${dm}"
            sudo systemctl disable "${dm}.service" || true
        fi
    done

    log_ok "SDDM with Pixie theme installed and enabled."
}

stow_dotfiles() {
    log_info "Stowing dotfiles to ~/..."

    # Pre-create ~/.config so stow folds into it rather than symlinking the whole dir.
    mkdir -p "${HOME}/.config"

    # stow dir = ~/dotfiles, package = .config, target = ~
    # Result: ~/.config/<app> → ../dotfiles/.config/<app>
    stow --restow --dir="${SCRIPT_DIR}" --target="${HOME}" .config
    log_ok "Dotfiles stowed."
}

configure_hyprland_host() {
    log_info "Configuring Hyprland host config..."

    local hosts_dir="${HOME}/.config/hypr/hosts"
    local host_conf="${hosts_dir}/$(hostname).conf"
    local current="${hosts_dir}/current.conf"

    if [[ ! -d "$hosts_dir" ]]; then
        log_warn "Hyprland hosts directory not found at ${hosts_dir}. Skipping."
        return 0
    fi

    if [[ ! -f "$host_conf" ]]; then
        log_warn "No host config found for '$(hostname)' at ${host_conf}."
        log_warn "Create it and re-run this function, or symlink manually:"
        log_warn "  ln -sf ${host_conf} ${current}"
        return 0
    fi

    ln -sf "$host_conf" "$current"
    log_ok "Hyprland host config set: $(hostname).conf → current.conf"
}

configure_virtualization() {
    log_info "Configuring virtualization..."

    sudo systemctl enable --now libvirtd
    log_ok "libvirtd service enabled and started."

    if groups "$USER" | grep -q '\blibvirt\b'; then
        log_ok "User already in libvirt group. Skipping."
    else
        sudo usermod -aG libvirt "$USER"
        log_ok "User added to libvirt group. Re-login required for virt-manager access."
    fi
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
    install_sddm_pixie
    stow_dotfiles
    configure_hyprland_host
    configure_virtualization
    set_shell
    cleanup

    echo ""
    log_ok "Installation complete!"
    log_info "Please reboot your system now: sudo reboot"
    echo ""
    log_info "After reboot:"
    log_info "  - SDDM (Pixie theme) will be your login screen"
    log_info "  - Select your MangoWM session and log in"
    log_info "  - Re-login once after reboot for libvirt group membership to take effect"
}

main "$@"
