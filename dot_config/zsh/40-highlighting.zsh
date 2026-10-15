# zsh-syntax-highlighting colours, from the Tokyo Night palette to match the
# starship prompt. Sourced after oh-my-zsh has loaded the plugin, so these
# override its defaults. Unknown commands are orange, like the prompt arrow
# after a failed command.
typeset -gA ZSH_HIGHLIGHT_STYLES

# commands
ZSH_HIGHLIGHT_STYLES[command]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[function]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#7aa2f7,italic'
ZSH_HIGHLIGHT_STYLES[arg0]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ff9e64'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#bb9af7'

# arguments
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[path]='fg=#c0caf5,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#bb9af7'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#bb9af7'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#bb9af7'

# punctuation and comments
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#89ddff'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#89ddff'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#565f89'
