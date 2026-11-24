#!/bin/bash
# SessionStart hook: Claude Code puts its launch PATH back after ~/.bashrc runs, so
# the Bash tool keeps the mise install dirs the terminal's hooks put there, and a
# project's mise.toml is ignored. Write a PATH without them, with mise's shims where
# they were, to $CLAUDE_ENV_FILE, which Claude Code sources before every command.
# The shims pick the version per directory each time a tool runs.
[ -n "$CLAUDE_ENV_FILE" ] || exit 0
data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
[ -d "$data/shims" ] || exit 0

# The shims go first, so mise's versions win over system ones, as with mise's own
# hooks; only its command-wrappers dir, which must precede them, stays ahead.
first= rest=
IFS=: read -ra dirs <<<"$PATH"
for d in "${dirs[@]}"; do
  case $d in
    "$data"/installs/*|"$data/shims") ;;
    "$data/command-wrappers/bin") first=$d: ;;
    *) rest=${rest:+$rest:}$d ;;
  esac
done
printf 'export PATH=%q\n' "$first$data/shims${rest:+:$rest}" >> "$CLAUDE_ENV_FILE"

# The terminal's mise hooks also export tool homes for the global versions; tools
# prefer them to what's on PATH (./mvnw uses JAVA_HOME, go uses GOROOT), so a
# project's pinned version would be ignored again. Clear those that point into
# mise's installs; ones set some other way stay.
for v in JAVA_HOME GOROOT GOBIN; do
  case ${!v} in
    "$data"/installs/*) printf 'unset %s\n' "$v" >> "$CLAUDE_ENV_FILE" ;;
  esac
done
