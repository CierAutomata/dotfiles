if status is-interactive
    # Commands to run in interactive sessions can go here
    set fish_greeting
     # Use starship prompt
    if command -v starship &>/dev/null
        starship init fish | source
    end

    set -gx PATH $PATH ~/.config/emacs/bin ~/.local/bin
    alias clear "printf '\033[2J\033[3J\033[1;1H'" # fix: kitty doesn't clear scrollback properly
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias vim="nvim"
    alias ssh="TERM=xterm-256color command ssh"
    # alias rebuild="sudo nixos-rebuild switch --impure --flake /home/(whoami)/nixos-config"
    alias rebuild="nh os switch -- --impure"
end