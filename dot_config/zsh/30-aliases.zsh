# Aliases and small functions

# eza instead of ls
if (( $+commands[eza] )); then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

# ff: fuzzy-find a file with a bat preview; eff: open the picked file in $EDITOR
if (( $+commands[fzf] )); then
  if (( $+commands[bat] || $+commands[batcat] )); then
    _ff_preview="${${commands[bat]:-$commands[batcat]}:t} --style=numbers --color=always {}"
  else
    _ff_preview="cat {}"
  fi
  ff() { fzf --preview "$_ff_preview" "$@"; }
  eff() {
    local file
    file=$(ff) && [[ -n $file ]] && $EDITOR "$file"
  }
fi

# Short names for everyday tools
if (( $+commands[nvim] )); then
  alias vim=nvim
  # n: nvim, or with no arguments open the current folder
  n() { if (( $# )); then nvim "$@"; else nvim .; fi; }
fi
(( $+commands[claude] )) && alias c=claude
(( $+commands[lazygit] )) && alias lg=lazygit
# ld is also the name of the linker; this alias only affects what you type,
# builds still call the real ld
(( $+commands[lazydocker] )) && alias ld=lazydocker
# z: same as cd (which zoxide took over), for zoxide muscle memory
alias z=cd

# o: open a file, folder or URL in its default app (the current folder if none given)
if [[ $OSTYPE == darwin* ]]; then
  o() { open "${@:-.}"; }
elif (( $+commands[xdg-open] )); then
  o() { xdg-open "${1:-.}" &>/dev/null &! }
fi
