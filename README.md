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

- installs `zsh`, `git`, `curl`, `git-delta`, `eza`, `fzf`, `zoxide` and powerline fonts (apt / pacman / dnf / brew)
  and sets zsh as the login shell — `run_onchange_before_10-install-packages.sh.tmpl`
  (may prompt for your sudo password). The package list lives in
  `.chezmoidata/packages.toml`; edit it and `chezmoi apply` to install new packages.
- clones [oh-my-zsh](https://ohmyz.sh/) into `~/.oh-my-zsh` — `.chezmoiexternal.toml`
  (don't run the oh-my-zsh installer; it would overwrite `~/.zshrc`)
- installs [herdr](https://herdr.dev) into `~/.local/bin` if missing — a chezmoi
  external in `.chezmoiexternal.toml.tmpl`, ignored via `.chezmoiignore` once the
  binary exists so herdr's own updater owns it from then on
- installs [mise](https://mise.jdx.dev) into `~/.local/bin` if no `mise` is installed
  yet (Debian/Ubuntu don't package it) — same external pattern as herdr; `mise
  self-update` keeps it current. A distro-packaged mise (Arch/Omarchy) is left alone.
- writes `~/.ssh/authorized_keys` from your GitHub public keys
  (`github.com/tkabala.keys`) — `private_dot_ssh/private_authorized_keys.tmpl`.
  The file is fully managed: add new keys on GitHub, then `chezmoi apply`.

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

## Updating

```sh
chezmoi update -v          # pull latest changes and apply
chezmoi add ~/.somefile    # start tracking a new file
chezmoi cd                 # open a shell in the source directory
chezmoi apply -R           # also force-refresh externals (git pull oh-my-zsh)
```

`run_once_` scripts run once per machine; `run_onchange_` scripts re-run whenever
their rendered content changes (for the package script: when the package list changes).
To re-run them: `chezmoi state delete-bucket --bucket=scriptState` (run_once)
and `chezmoi state delete-bucket --bucket=entryState` (run_onchange).
