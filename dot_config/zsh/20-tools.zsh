# Tool integrations

(( $+commands[starship] )) && eval "$(starship init zsh)"

(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"
# fzf --zsh needs fzf 0.48+; older distro builds just skip it
(( $+commands[fzf] )) && source <(fzf --zsh 2>/dev/null)

# try: loaded on first use to keep shell startup fast
if (( $+commands[try] )); then
  try() {
    unfunction try
    eval "$(command try init ~/Work/tries)"
    try "$@"
  }
fi
