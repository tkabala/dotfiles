# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Restore on a new machine

### 1. Install chezmoi and apply in one step

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply tkabala
```

This installs chezmoi to `./bin`, clones `github.com/tkabala/dotfiles`
into `~/.local/share/chezmoi`, and applies the dotfiles to your home directory.

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
```
