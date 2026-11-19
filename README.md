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
  a C compiler, `neovim` and `starship` (both except apt) and the distro's command-not-found
  handler (`pkgfile` or `command-not-found`) (apt / pacman / brew),
  and sets zsh as the login shell — `run_onchange_before_10-install-packages.sh.tmpl`
  (may prompt for your sudo password). The package list lives in
  `.chezmoidata/packages.toml`; edit it and `chezmoi apply` to install new packages.
- on macOS, installs [Homebrew](https://brew.sh) first if it's missing: it's the package
  manager used there. Linux doesn't use Homebrew.
- clones [oh-my-zsh](https://ohmyz.sh/) into `~/.oh-my-zsh` — `.chezmoiexternal.toml`
  (don't run the oh-my-zsh installer; it would overwrite `~/.zshrc`), plus the
  `zsh-autosuggestions` and `zsh-syntax-highlighting` plugins into its `custom/plugins`
- installs [herdr](https://herdr.dev) into `~/.local/bin` if missing — a chezmoi
  external in `.chezmoiexternal.toml.tmpl`, ignored via `.chezmoiignore` once the
  binary exists so herdr's own updater owns it from then on
- installs [mise](https://mise.jdx.dev) into `~/.local/bin` if no `mise` is installed
  yet (Debian/Ubuntu don't package it) — same external pattern as herdr; `mise
  self-update` keeps it current. A distro-packaged mise (Arch) is left alone.
  The global tool list, `~/.config/mise/config.toml`, is tracked too (as
  `dot_config/mise/config.toml.tmpl`), and `run_onchange_after_20-mise-install.sh.tmpl`
  runs `mise install` whenever it changes. It holds `gh`, node, go, uv and the rest on every
  machine, plus neovim and [starship](https://starship.rs) on Debian/Ubuntu (too old /
  not packaged there). Work machines also get java (Corretto 21), maven, kubectl, helm, aws-cli, govc,
  vault, `glab` and playwright-cli. `mise up` updates them. `~/.zshrc` activates
  mise before oh-my-zsh, so the `gh` and `glab` plugins set up their completions.
  `mise use -g` edits the file in your home directory, not the repo: copy the change
  into `dot_config/mise/config.toml.tmpl` so other machines get it.
- the starship prompt config is `~/.config/starship.toml`, starship's
  [Tokyo Night](https://starship.rs/presets/tokyo-night) preset (needs a Nerd Font).
- the LazyVim config in `~/.config/nvim` is tracked except
  `lazy-lock.json` and the desktop's theme plugin files; `lazyvim.json` is only created if missing.
- writes `~/.ssh/authorized_keys` from your GitHub public keys
  (`github.com/tkabala.keys`) — `private_dot_ssh/private_authorized_keys.tmpl`.
  This happens on every machine, so all your devices can SSH into each other.
  The file is fully replaced on each apply, so keys added by hand are lost:
  GitHub is the single place to add or revoke a device's key, followed by
  `chezmoi apply` on each machine. Keys only one machine should accept (e.g. a
  server's root key) go in that machine's untracked `~/.ssh/authorized_keys.local`,
  which is appended — not on GitHub, which would let them into every machine.

The first prompt, "Minimal install", is for servers and containers: see below.

### Servers and containers (minimal install)

A minimal install manages only `~/.ssh/authorized_keys` (GitHub keys plus
`authorized_keys.local`): no packages, no shell change, no oh-my-zsh/mise/herdr, no
other dotfiles (`.chezmoiignore` ignores everything else, scripts included). As root:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin init --apply \
  --promptBool "Minimal install (only SSH authorized_keys)=true" tkabala
# keep keys in sync with GitHub daily
echo '17 4 * * * root /usr/local/bin/chezmoi update --force >/dev/null' > /etc/cron.d/chezmoi
```

chezmoi has git built in, so the machine doesn't need git.

On a **Proxmox VE** host, `/root/.ssh/authorized_keys` is a symlink to
`/etc/pve/priv/authorized_keys`, and `pveproxy` (via `pvecm updatecerts`) merges a
regular file there back into it on every start. So on PVE (detected by
`/usr/bin/pmxcfs`) chezmoi leaves the symlink alone and
`run_after_30-pve-authorized-keys.sh.tmpl` writes the keys into
`/etc/pve/priv/authorized_keys` instead. That file holds the node's own `root@<node>`
key: put it, and other servers' keys, in `/root/.ssh/authorized_keys.local` before
the first apply. In a cluster the file is shared by all nodes, so each node's
`authorized_keys.local` must list every node's root key.

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
  number above the managed `10-`–`40-` files to load after them. The directory isn't
  `exact_`, so chezmoi leaves unmanaged files in it alone.
- `~/.gitconfig.local` — per-machine git settings (credential helpers, etc.),
  included at the end of `~/.gitconfig` so it overrides the repo's settings.
  Git skips the include if the file is missing.
- `~/.ssh/config.local` — per-machine SSH hosts and overrides, included at the top
  of `~/.ssh/config` (ssh uses the first value it finds, so it wins over the repo's
  `Host *` defaults). SSH skips the include if the file is missing. The managed
  `Host *` sends `LC_ALL=C.UTF-8` so servers without the client's locale (e.g.
  `en_GB.UTF-8`, forwarded by the system's `SendEnv LANG LC_*`) don't print
  locale warnings.

`~/.ssh/authorized_keys` is not a local override: it's managed on every machine
(see above).

When applying to an existing machine for the first time, back up the dotfiles it
already has (including `~/.ssh/authorized_keys`) and run `chezmoi diff` before
`chezmoi apply`.

## herdr

New interactive zsh shells start herdr (not inside herdr itself, VS Code or
JetBrains terminals). Before launching, `~/.local/bin/herdr-update-check` checks
herdr's update channel at most once a day and runs `herdr update --handoff` if a
newer release is out — herdr can't update itself from inside a session.

- `HERDR_NO_AUTOSTART=1 zsh` — a shell without herdr
- `HERDR_UPDATE_INTERVAL=<seconds>` — change how often to check (default 86400)
- `herdr-update-check --force` — check now, from a shell outside herdr

The config, `~/.config/herdr/config.toml`, is tracked as `dot_config/herdr/config.toml.tmpl`:
no first-run onboarding, new panes and tabs in the current directory, no close
confirmation, and the mobile layout below 100 columns. herdr's logs, sockets
and session files next to it aren't tracked.

Put machine-specific herdr settings (e.g. extra `[[keys.command]]` bindings) in
`~/.config/herdr/config.local.toml`, which isn't tracked. It's appended to the config at
`chezmoi apply`, so re-run apply after editing it.

## Claude Code status line

`~/.claude/statusline.sh` draws Claude Code's status line as three full-width, lualine-style
rows: pills hug the left and right edges and the gap between is filled with a bar. Left/right:
hostname, directory, worktree, clean/dirty, branch, +/- lines, ahead/behind | open PR/MR as a link;
session name, time running, model, fast mode, thinking effort | context bar; prompt-cache
countdown, hit ratio and misses | 5-hour/weekly usage with reset times. Needs `jq`, `git` and
a Nerd Font (pills carry icons). Colors are ANSI palette indices, so the bar follows the terminal's color
scheme. Width comes from `$COLUMNS` or the terminal's tty (120 if neither is found);
`STATUSLINE_MARGIN` (default 4, since Claude Code truncates rows wider than its status area) leaves columns free at the right edge. The PR/MR and cache
figures come from Claude Code itself, so the PR segment needs `gh` or `glab` logged in.
On narrow screens (under `STATUSLINE_NARROW` columns, default 100: a phone over ssh, a split
pane) the hostname, session name and context bar are left out, and rows that still don't fit
wrap: pills move onto extra rows instead of being cut off, and a pill wider than the whole
screen is shortened with `…`.

`dot_claude/modify_private_settings.json` sets only these keys in `~/.claude/settings.json`
and leaves the rest of the file to Claude Code:

- `statusLine`: this status line (an old `subagentStatusLine` entry is removed, since Claude
  Code no longer supports it)
- `theme`: `custom:tokyo-night`, from `~/.claude/themes/tokyo-night.json`
- `showTurnDuration`: the "Cooked for 1m 6s" line after each response, on every machine
- `awaySummaryEnabled: false`: no session recap when you come back after 5+ minutes away
- `idleCompaction: false`: a long conversation isn't compacted while the session sits idle
- `env.CLAUDE_CODE_SHELL=/bin/bash`: Claude's commands run in bash, not zsh
- `env.DISABLE_AUTOUPDATER=1`: Claude Code comes from mise, `mise up claude` updates it
- `env.CLAUDE_CODE_PLUGIN_DIRS`: loads the mods in `~/.claude/mods` in every session

### Mods

`dot_claude/mods/` holds Claude Code mods (plugins of function hooks), each loaded from its
folder through `CLAUDE_CODE_PLUGIN_DIRS`; a new mod also needs its folder added there.

- `usage-planner`: gives Claude a `usage_limits` tool reporting the Pro/Max 5-hour and weekly
  usage windows (percent used, time to reset, learned cost per turn, turns left), and sends
  it a note when a window first crosses 60/80/90% (5-hour) or 50/75/90% (weekly), with a
  toast for you. Thresholds are `THRESHOLDS` in `hooks/register.ts`; tests run with
  `claude plugin test ~/.claude/mods/usage-planner`.
- `cache-keepalive`: keeps prompt caches from expiring while work runs. 50 minutes after a
  main-session turn it sends "what's the status of the task?" (inside the 1-hour cache TTL),
  at most 3 times without a prompt from you. Subagents waiting on background work (5-minute
  TTL) get an "ok" message ~90 s before expiry, for up to 30 minutes, with the main-session
  notification each one causes dropped. A busy subagent whose cache runs out mid-command
  gets a one-time toast (long command or hang). `/keepalive on|off|status`.

- Preview: `echo '{"cwd":"'$PWD'"}' | ~/.claude/statusline.sh`

## Testing

`.github/workflows/test.yml` applies the dotfiles to fresh Debian 13, Ubuntu 26.04
(as a work machine) and Arch containers, and to a macOS runner, on every push
and weekly, then checks that zsh starts cleanly with all the tools —
`.github/scripts/test-apply.sh`. To run one locally:

```sh
docker run --rm -v "$PWD:/src:ro" -e GITHUB_TOKEN="$(gh auth token)" debian:13 \
  /src/.github/scripts/test-apply.sh false   # true: as a work machine
```

## Updating

```sh
chezmoi update -v          # pull latest changes and apply
chezmoi add ~/.somefile    # start tracking a new file
chezmoi cd                 # open a shell in the source directory
chezmoi apply -R           # also force-refresh externals (git pull oh-my-zsh and its plugins)
chezmoi merge ~/.somefile  # file changed both here and in the repo: merge in nvim -d
chezmoi upgrade            # update chezmoi itself
```

`run_once_` scripts run once per machine; `run_onchange_` scripts re-run whenever
their rendered content changes (for the package script: when the package list changes).
To re-run them: `chezmoi state delete-bucket --bucket=scriptState` (run_once)
and `chezmoi state delete-bucket --bucket=entryState` (run_onchange).
