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

- installs `zsh`, `git`, `curl` and powerline fonts (apt / pacman / dnf / brew)
  and sets zsh as the login shell — `run_once_before_10-install-packages.sh.tmpl`
  (may prompt for your sudo password)
- clones [oh-my-zsh](https://ohmyz.sh/) into `~/.oh-my-zsh` — `.chezmoiexternal.toml`
  (don't run the oh-my-zsh installer; it would overwrite `~/.zshrc`)

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

`run_once_` scripts run once per machine; editing a script makes it run again.
To re-run all of them: `chezmoi state delete-bucket --bucket=scriptState`.
