#!/bin/bash
pacman -Qqm > ~/.dotfiles/pkgs-backup/installed_packages_aur
pacman -Qqe > ~/.dotfiles/pkgs-backup/installed_packages
