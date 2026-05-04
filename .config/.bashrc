PATH=$PATH:~/bin
alias la="ls -la"
alias ".."="cd .."
alias rebuild="sudo nixos-rebuild switch --impure --flake /home/briest/nixos-config"
alias vim="nvim"
#QT_QPA_PLATFORMTHEME=gtk3
PS1="\[\033[1;32m\][\u@\h:\w]\\$\[\033[0m\] "
