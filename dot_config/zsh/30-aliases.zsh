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
