#!/bin/bash
# Apply these dotfiles to a fresh machine and check the result. CI runs it in clean
# Linux containers (as root) and on a macOS runner (as the runner user):
#   .github/scripts/test-apply.sh [work]     # "work" answers yes to "Is this a work machine"
#   .github/scripts/test-apply.sh minimal    # a server/container: only authorized_keys, as root
# Locally: docker run --rm -v "$PWD:/src:ro" debian:13 /src/.github/scripts/test-apply.sh false
#
# As root it installs sudo/git/curl, creates a `tester` user with passwordless sudo
# (like a real laptop: the install script uses sudo) and re-runs itself as that user.
set -euo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${1:-${WORK:-false}}
[ "$WORK" = work ] && WORK=true

if [ "$WORK" = minimal ]; then
  # Like a fresh LXC: root, curl only. Nothing else may be installed or changed.
  if command -v apt-get >/dev/null; then
    apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -yq curl ca-certificates
  else
    pacman -Sy --noconfirm --needed curl
  fi
  step() { printf '\n=== %s\n' "$*"; }
  # A machine-only key (like another server's root key), appended to the GitHub ones.
  mkdir -p -m 700 /root/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExtraLocalKeyForTesting000000000000000 local-extra" \
    > /root/.ssh/authorized_keys.local
  step "chezmoi init --apply (minimal)"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
  chezmoi --source="$SRC" init --apply --promptBool "Minimal install (only SSH authorized_keys)=true"
  step "nothing left to apply"
  chezmoi --source="$SRC" verify
  step "only authorized_keys is managed"
  managed=$(chezmoi --source="$SRC" managed --include=files,dirs,symlinks,externals | tr '\n' ' ')
  echo "$managed"
  [ "$managed" = ".ssh .ssh/authorized_keys " ]
  step "authorized_keys has GitHub keys and the local extra"
  grep -c '^ssh-' /root/.ssh/authorized_keys
  grep -q 'local-extra$' /root/.ssh/authorized_keys
  [ "$(grep -c '^ssh-' /root/.ssh/authorized_keys)" -ge 2 ]
  step "no packages, no shell change"
  for t in zsh git nvim mise; do ! command -v $t >/dev/null || { echo "installed: $t" >&2; exit 1; }; done
  [ ! -e /root/.oh-my-zsh ] && [ ! -e /root/.local/bin/mise ] && [ ! -e /root/.zshrc ]
  [ "$(getent passwd root | cut -d: -f7)" = /bin/bash ]
  step "all checks passed"
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  case " $ID ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -q && apt-get install -yq sudo git curl ca-certificates ;;
    *" arch "*) pacman -Syu --noconfirm --needed sudo git curl ;;
    *) echo "unknown distro $ID" >&2; exit 1 ;;
  esac
  useradd -m -s /bin/bash tester
  printf '%s\n' 'tester ALL=(ALL) NOPASSWD:ALL' 'Defaults env_keep += "DEBIAN_FRONTEND"' > /etc/sudoers.d/tester
  # A copy the user owns: git refuses to work in a repo owned by someone else.
  cp -r "$SRC" /home/tester/dotfiles && chown -R tester: /home/tester/dotfiles
  exec sudo -u tester -H env DEBIAN_FRONTEND=noninteractive GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    /home/tester/dotfiles/.github/scripts/test-apply.sh "$WORK"
fi

# mise downloads from GitHub's API: a token avoids its anonymous rate limit.
[ -n "${GITHUB_TOKEN:-}" ] && export MISE_GITHUB_TOKEN=$GITHUB_TOKEN

step() { printf '\n=== %s\n' "$*"; }
cz() { "$HOME/.local/bin/chezmoi" --source="$SRC" "$@"; }

step "chezmoi init --apply (work=$WORK)"
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
cz init --apply \
  --promptBool "Minimal install (only SSH authorized_keys)=false" \
  --promptBool "Is this a work machine=$WORK" --promptString "Git email=ci@example.com"

step "nothing left to apply"
cz verify

step "login shell is zsh"
shell=$(if [ "$(uname)" = Darwin ]; then dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'
        else getent passwd "$(id -un)" | cut -d: -f7; fi)
echo "$shell"
[ "$(basename "$shell")" = zsh ]

step "interactive zsh starts cleanly and has the tools"
tools="git nvim fzf zoxide rg bat eza delta starship mise gh uv"
[ "$WORK" = true ] && tools="$tools glab java mvn kubectl helm aws govc vault"
# zsh -i without a terminal warns that it can't enable zle; anything else on stderr fails.
stderr=$(mktemp)
status=0
HERDR_NO_AUTOSTART=1 zsh -i -c "
  for t in $tools; do
    [[ \$t == bat ]] && (( ! \$+commands[bat] )) && t=batcat
    whence -p \$t >/dev/null || { echo \"missing: \$t\" >&2; exit 1; }
  done
  gh --version | head -1
  nvim --version | head -1
" 2>"$stderr" || status=$?
if [ "$status" -ne 0 ] || grep -v "can't change option: zle" "$stderr" >&2; then
  echo "zsh exited with $status, or printed errors (above)" >&2
  exit 1
fi

step "git settings"
[ "$(git config --get pull.rebase)" = true ]
git config --get-all credential.https://github.com.helper | grep -q 'gh auth git-credential'

step "all checks passed"
