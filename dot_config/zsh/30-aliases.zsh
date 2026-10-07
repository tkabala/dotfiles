# Aliases and small functions

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
