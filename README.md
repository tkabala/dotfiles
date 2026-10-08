# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Restore on a new machine

### 1. Install chezmoi and apply in one step

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply tkabala
```

This installs chezmoi to `~/.local/bin`, clones `github.com/tkabala/dotfiles`
into `~/.local/share/chezmoi`, and applies the dotfiles to your home directory.

On first apply it also:

- installs `zsh`, `git`, `curl`, `jq`, `git-delta`, `eza`, `fzf`, `zoxide`, `ripgrep`, `fd`, `bat`,
  a C compiler, `neovim` (except apt) and powerline fonts (apt / pacman / dnf / brew),
  plus `glab` on work machines,
  and sets zsh as the login shell — `run_onchange_before_10-install-packages.sh.tmpl`
  (may prompt for your sudo password). The package list lives in
  `.chezmoidata/packages.toml`; edit it and `chezmoi apply` to install new packages.
- clones [oh-my-zsh](https://ohmyz.sh/) into `~/.oh-my-zsh` — `.chezmoiexternal.toml`
  (don't run the oh-my-zsh installer; it would overwrite `~/.zshrc`), plus the
  `zsh-autosuggestions` and `zsh-syntax-highlighting` plugins into its `custom/plugins`
- installs [starship](https://starship.rs) into `~/.local/bin` if no `starship` is
  installed yet (Debian 12 / Ubuntu 24.04 and Fedora don't package it) — same external
  pattern as herdr. The prompt config is `~/.config/starship.toml`, an agnoster-style powerline
  prompt (needs a Nerd Font); its git segment comes from `~/.config/starship/agnoster-git`.
- installs [herdr](https://herdr.dev) into `~/.local/bin` if missing — a chezmoi
  external in `.chezmoiexternal.toml.tmpl`, ignored via `.chezmoiignore` once the
  binary exists so herdr's own updater owns it from then on
- installs [mise](https://mise.jdx.dev) into `~/.local/bin` if no `mise` is installed
  yet (Debian/Ubuntu don't package it) — same external pattern as herdr; `mise
  self-update` keeps it current. A distro-packaged mise (Arch/Omarchy) is left alone.
- on Debian/Ubuntu, whose neovim is too old for LazyVim, installs the upstream
  neovim release into `~/.local/opt/nvim` (linked from `~/.local/bin/nvim`), refreshed
  weekly by chezmoi. The LazyVim config in `~/.config/nvim` is tracked except
  `lazy-lock.json` and Omarchy's theme files; `lazyvim.json` is only created if missing.
- writes `~/.ssh/authorized_keys` from your GitHub public keys
  (`github.com/tkabala.keys`) — `private_dot_ssh/private_authorized_keys.tmpl`.
  This happens on every machine, so all your devices can SSH into each other.
  The file is fully replaced on each apply, so keys added by hand are lost:
  GitHub is the single place to add or revoke a device's key, followed by
  `chezmoi apply` on each machine.

## herdr

New interactive zsh shells start herdr (not inside herdr itself, VS Code or
JetBrains terminals). Before launching, `~/.local/bin/herdr-update-check` checks
herdr's update channel at most once a day and runs `herdr update --handoff` if a
newer release is out — herdr can't update itself from inside a session.

- `HERDR_NO_AUTOSTART=1 zsh` — a shell without herdr
- `HERDR_UPDATE_INTERVAL=<seconds>` — change how often to check (default 86400)
- `herdr-update-check --force` — check now, from a shell outside herdr

### 2. Or step by step

Install chezmoi (pick one):

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin   # generic
brew install chezmoi                                       # macOS / Homebrew
sudo pacman -S chezmoi                                     # Arch
```

Initialize from this repo, review, and apply:

```sh
chezmoi init git@github.com:tkabala/dotfiles.git   # or: chezmoi init tkabala
chezmoi diff                                       # preview changes
chezmoi apply -v                                   # write files to ~
```

## Machine-local overrides

This repo is public, so per-machine settings live in untracked files that chezmoi
doesn't manage:

- `~/.config/zsh/*-local.zsh` (e.g. `60-local.zsh`) — per-machine env, aliases, `PATH`
  and tool init. `~/.zshrc` sources `~/.config/zsh/*.zsh` in name order, so pick a
  number above the managed `10-`–`30-` files to load after them. The directory isn't
  `exact_`, so chezmoi leaves unmanaged files in it alone.
- `~/.gitconfig.local` — per-machine git settings (credential helpers, etc.),
  included at the end of `~/.gitconfig` so it overrides the repo's settings.
  Git skips the include if the file is missing.

`~/.ssh/authorized_keys` is not a local override: it's managed on every machine
(see above).

When applying to an existing machine for the first time, back up the dotfiles it
already has (including `~/.ssh/authorized_keys`) and run `chezmoi diff` before
`chezmoi apply`.

## Claude Code status line

`~/.claude/statusline.sh` draws Claude Code's status line. It reads the session JSON
Claude Code pipes in and prints three powerline rows: directory and git state (worktree,
clean/dirty, branch, +/- lines, ahead/behind, GitHub PR via `gh` or GitLab MR via `glab`);
model, thinking effort, context bar and compaction count; prompt-cache countdown and
5-hour/weekly usage with reset times. Needs `jq`, `git` and a powerline font; `gh` and
`glab` are optional — the forge is picked from the `origin` host (self-hosted: whichever
CLI is logged in to it).

`dot_claude/modify_private_settings.json` sets only the `statusLine` key and
`env.CLAUDE_CODE_SHELL=/bin/bash` (Claude's commands run in bash, not zsh) in
`~/.claude/settings.json` and leaves the rest of the file to Claude Code.

- `CLAUDE_STATUSLINE_CACHE_TTL=<seconds>` — prompt cache TTL to count down (default 3600)
- `CLAUDE_STATUSLINE_PR_TTL=<seconds>` — how long a PR/MR lookup is cached (default 60)
- Preview: `echo '{"cwd":"'$PWD'"}' | ~/.claude/statusline.sh`

## Updating

```sh
chezmoi update -v          # pull latest changes and apply
chezmoi add ~/.somefile    # start tracking a new file
chezmoi cd                 # open a shell in the source directory
chezmoi apply -R           # also force-refresh externals (git pull oh-my-zsh and its plugins)
```

`run_once_` scripts run once per machine; `run_onchange_` scripts re-run whenever
their rendered content changes (for the package script: when the package list changes).
To re-run them: `chezmoi state delete-bucket --bucket=scriptState` (run_once)
and `chezmoi state delete-bucket --bucket=entryState` (run_onchange).
