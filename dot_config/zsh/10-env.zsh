# Environment

# Editor for git, sudoedit, crontab -e and friends
if (( $+commands[nvim] )); then
  export EDITOR=nvim
else
  export EDITOR=vim
fi
export VISUAL=$EDITOR
export SUDO_EDITOR=$EDITOR
