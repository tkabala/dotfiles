# Environment

# Editor for git, sudoedit, crontab -e and friends
if (( $+commands[nvim] )); then
  export EDITOR=nvim
else
  export EDITOR=vim
fi
export VISUAL=$EDITOR
export SUDO_EDITOR=$EDITOR

# bat: colored man pages. Debian/Ubuntu install it as batcat.
if (( $+commands[bat] || $+commands[batcat] )); then
  (( $+commands[bat] )) || alias bat=batcat
  export BAT_THEME=ansi
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | ${${commands[bat]:-$commands[batcat]}:t} -l man -p'"
fi
