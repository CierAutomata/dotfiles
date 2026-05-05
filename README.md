# dotfiles

MangoWM / Hyprland dotfiles for Fedora 42, managed with GNU Stow.

## Repository layout

```
~/dotfiles/
├── .config/           # stow package → ~/.config/
│   ├── hypr/
│   │   ├── hyprland.conf
│   │   └── hosts/
│   │       ├── desktop.conf   # host-specific configs
│   │       ├── laptop.conf
│   │       └── current.conf   # local symlink, not tracked
│   ├── fish/
│   ├── kitty/
│   └── ...
├── sddm-theme/        # Pixie SDDM theme + theme.conf
├── .stowrc            # stow defaults (--target=~ --restow)
├── .gitignore
└── Fedora-Install.sh  # automated install script
```

## Fresh install

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
chmod +x Fedora-Install.sh
./Fedora-Install.sh
```

The script handles:
- DNF configuration & third-party repos (RPM Fusion, Terra, TekkRPM)
- All system packages, audio stack, virtualization
- SDDM with Pixie theme
- Stowing dotfiles (see below)
- Hyprland host config symlink
- libvirtd setup + libvirt group membership
- Fish as default shell

## Dotfile management (stow)

Dotfiles are symlinked into `~` via GNU Stow. The `.stowrc` in the repo root sets
`--target=~` and `--restow` as defaults.

**Initial stow / re-stow everything:**
```bash
cd ~/dotfiles
stow .config
```

**Re-stow a single app:**
```bash
cd ~/dotfiles
stow .config/hypr
```

**Remove symlinks for an app:**
```bash
cd ~/dotfiles
stow --delete .config/hypr
```

## Hyprland host config

`hyprland.conf` sources `~/.config/hypr/hosts/current.conf`, which is a local
symlink pointing to the config for the current machine. The symlink is not tracked
in git.

**The install script sets this automatically.** For manual setup or when adding a
new host:

1. Create a host config:
   ```
   ~/.config/hypr/hosts/<hostname>.conf
   ```

2. Set the symlink:
   ```bash
   ln -sf ~/.config/hypr/hosts/$(hostname).conf ~/.config/hypr/hosts/current.conf
   ```

3. In `hyprland.conf`, make sure this line is present:
   ```
   source = ~/.config/hypr/hosts/current.conf
   ```

To check which host config is currently active:
```bash
readlink ~/.config/hypr/hosts/current.conf
```

## Adding a new machine

1. Clone the repo: `git clone <repo-url> ~/dotfiles`
2. Add a host config at `.config/hypr/hosts/<new-hostname>.conf`
3. Run `./Fedora-Install.sh` — it will stow everything and set the symlink automatically.
