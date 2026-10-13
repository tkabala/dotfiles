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

# History. oh-my-zsh keeps 50000 commands in memory but only saves 10000 to
# ~/.zsh_history; keep 100000 in both. It already records timestamps, shares
# history between open shells and skips commands that start with a space.
HISTSIZE=100000
SAVEHIST=100000
setopt hist_ignore_all_dups   # a repeated command replaces its older copy
setopt hist_reduce_blanks     # "ls   -l" is saved as "ls -l"
