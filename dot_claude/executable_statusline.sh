#!/usr/bin/env bash
# Claude Code status line.
# Claude Code pipes session JSON on stdin and shows whatever this prints:
#   1: cwd · worktree · clean/dirty · branch · +/- lines · ahead/behind · PR
#   2: model · thinking effort · context bar · compactions
#   3: prompt-cache countdown · 5h usage + reset · weekly usage + reset
# Needs jq and git; gh / glab are optional (PR / MR segment). Keep it bash 3.2-safe for macOS.
#
#   CLAUDE_STATUSLINE_CACHE_TTL=<seconds>  prompt cache TTL to count down (default 3600)
#   CLAUDE_STATUSLINE_PR_TTL=<seconds>     how long a PR lookup is reused (default 60)

input=$(cat)
command -v jq >/dev/null 2>&1 || { echo "statusline: jq not found"; exit 0; }

# --- session data -----------------------------------------------------------

eval "$(jq -r '
  def dur: floor as $s
    | if $s <= 0 then "now"
      else [($s / 86400 | floor), ($s % 86400 / 3600 | floor), ($s % 3600 / 60 | floor)] as [$d, $h, $m]
        | [if $d > 0 then "\($d)d" else empty end, if $h > 0 then "\($h)h" else empty end, "\($m)m"] | join(" ")
      end;
  def num: try tonumber catch null;
  def pct: if . == null then "" else "\(. * 10 | round / 10)%" end;
  def kilo: if . >= 1000 then "\(. / 1000 | round)k" else "\(. | round)" end;
  def window(f): (.rate_limits // {} | f // {}) as $l
    | [($l.used_percentage | num | pct),
       ($l.resets_at | num | if . == null then "" else . - now | dur end)];

  (.context_window // {}) as $cw
  | ($cw.context_window_size | num) as $size
  | ($cw.current_usage | if type == "object"
       then (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
       else null end) as $used
  | ($cw.used_percentage | num // (if $used and $size then $used * 100 / $size else null end)) as $ctx_pct
  | window(.five_hour) as [$five, $five_reset]
  | window(.seven_day) as [$week, $week_reset]
  | @sh "cwd=\(.workspace.current_dir // .cwd // "")",
    @sh "transcript=\(.transcript_path // "")",
    @sh "model=\(.model | if type == "object" then .display_name // .id else . end // "")",
    @sh "effort=\(.effort.level // "")",
    @sh "ctx_pct=\($ctx_pct // "" | if . == "" then . else round end)",
    @sh "ctx_tokens=\(if $size == null then ""
                      else "\(($used // (($ctx_pct // 0) * $size / 100)) | kilo)/\($size | kilo)" end)",
    @sh "five=\($five)", @sh "five_reset=\($five_reset)",
    @sh "week=\($week)", @sh "week_reset=\($week_reset)"
' <<<"$input" 2>/dev/null)"
cwd=${cwd:-$PWD}

# --- powerline rendering ----------------------------------------------------

RESET=$'\e[0m'
SEP=$'\xee\x82\xb0' CAP=$'\xee\x82\xb2'  # powerline U+E0B0 / U+E0B2 (needs a powerline/Nerd font)
fg() { printf '\e[38;2;%d;%d;%dm' $((16#${1:0:2})) $((16#${1:2:2})) $((16#${1:4:2})); }
bg() { printf '\e[48;2;%d;%d;%dm' $((16#${1:0:2})) $((16#${1:2:2})) $((16#${1:4:2})); }

# Palette.
DARK=0b0b0b LIGHT=c3c2b7 GREY=3a3a38 BLUE=3987e5 ORANGE=d95926
GREEN=199e70 AMBER=c98500 PINK=d55181 PURPLE=9085e9 RED=e66767

seg_bg=() seg_fg=() seg_text=()
# seg <bg> <fg> <text> — queue a segment; empty text skips it.
seg() {
  [ -n "$3" ] || return 0
  seg_bg+=("$1") seg_fg+=("$2") seg_text+=("$3")
}
# Print the queued segments as one powerline row and start a new row.
flush() {
  local n=${#seg_text[@]} i out
  [ "$n" -gt 0 ] || return 0
  out="$(fg "${seg_bg[0]}")$CAP"
  for ((i = 0; i < n; i++)); do
    out+="$(bg "${seg_bg[i]}")$(fg "${seg_fg[i]}") ${seg_text[i]} "
    if [ $((i + 1)) -lt "$n" ]; then
      out+="$(fg "${seg_bg[i]}")$(bg "${seg_bg[i + 1]}")$SEP"
    else
      out+="$RESET$(fg "${seg_bg[i]}")$SEP$RESET"
    fi
  done
  printf '%s\n' "$out"
  seg_bg=() seg_fg=() seg_text=()
}

# --- line 1: location and git -----------------------------------------------

seg "$BLUE" "$DARK" "${cwd/#"$HOME"/\~}"

git_() { git -C "$cwd" --no-optional-locks "$@" 2>/dev/null; }

# Print the open review for the current branch: "#12 open ✓" (GitHub PR) or
# "!12 open" (GitLab MR). The forge comes from the origin remote: a github/gitlab
# origin host picks gh/glab; any other host (self-hosted, or an SSH alias resolved
# via `ssh -G`) uses whichever CLI is logged in to it; no origin tries both.
review_lookup() {
  local url host ssh_url providers p out
  url=$(git_ remote get-url origin)
  host=$(sed -E 's#^[A-Za-z+]+://##; s#^[^@/]*@##; s#[:/].*##' <<<"$url" | tr '[:upper:]' '[:lower:]')
  case "$url" in
    *://*) [ "${url%%://*}" = ssh ] && ssh_url=1 || ssh_url= ;;
    *) ssh_url=1 ;;
  esac
  case "$host" in *github* | *gitlab*) ;; ?*)
    [ -n "$ssh_url" ] && host=$(ssh -G "$host" 2>/dev/null | awk '$1 == "hostname" { print tolower($2); exit }') ;;
  esac
  case "$host" in
    "") providers="gh glab" ;;
    *github*) providers=gh ;;
    *gitlab*) providers=glab ;;
    *) for p in glab gh; do
         command -v "$p" >/dev/null 2>&1 && "$p" auth status --hostname "$host" >/dev/null 2>&1 && providers="$providers $p"
       done ;;
  esac
  for p in $providers; do
    command -v "$p" >/dev/null 2>&1 || continue
    case "$p" in
      gh) gh pr view --json number,state,isDraft,reviewDecision --jq '
            "#\(.number) " + (if .isDraft then "draft" else .state | ascii_downcase end)
            + ({APPROVED: " ✓", CHANGES_REQUESTED: " ✗", REVIEW_REQUIRED: " ?"}[.reviewDecision // ""] // "")
          ' && return ;;
      glab) out=$(glab mr view --output json) && [ -n "$out" ] && jq -r '
            "!\(.iid) " + (if .draft then "draft" else {opened: "open"}[.state] // .state end)
            + ({mergeable: " ✓", not_approved: " ?", requested_changes: " ✗"}[.detailed_merge_status // ""] // "")
          ' <<<"$out" && return ;;
    esac
  done
}
if paths=$(git_ rev-parse --show-toplevel --absolute-git-dir --git-common-dir); then
  top=$(sed -n 1p <<<"$paths") gitdir=$(sed -n 2p <<<"$paths") common=$(sed -n 3p <<<"$paths")
  status=$(git_ status --porcelain=v2 --branch)
  branch=$(sed -n 's/^# branch\.head //p' <<<"$status")
  read -r ahead behind <<<"$(sed -n 's/^# branch\.ab +\([0-9]*\) -\([0-9]*\)$/\1 \2/p' <<<"$status")"
  shortstat=$(git_ diff --shortstat HEAD)
  added=$(sed -n 's/.* \([0-9]*\) insertion.*/\1/p' <<<"$shortstat")
  removed=$(sed -n 's/.* \([0-9]*\) deletion.*/\1/p' <<<"$shortstat")

  # A linked worktree's git dir lives under the main repo's common dir.
  case "$common" in /*) ;; *) common="$cwd/$common" ;; esac
  [ "$gitdir" != "$(cd "$common" 2>/dev/null && pwd -P)" ] && seg "$ORANGE" "$DARK" "𖠰 ${top##*/}"

  if grep -qv '^#' <<<"$status"; then seg "$GREY" "$LIGHT" "✗"; else seg "$GREY" "$LIGHT" "✓"; fi
  seg "$GREEN" "$DARK" "⎇ $branch"
  [ -n "$shortstat" ] && seg "$AMBER" "$DARK" "+${added:-0} -${removed:-0}"
  ab=""
  [ "${ahead:-0}" -gt 0 ] && ab="↑$ahead"
  [ "${behind:-0}" -gt 0 ] && ab="${ab:+$ab }↓$behind"
  seg "$PINK" "$DARK" "$ab"

  # PR/MR for this branch, looked up in the background and cached so gh/glab never
  # block the status line; the first refresh after a branch switch shows nothing.
  if { command -v gh || command -v glab; } >/dev/null 2>&1 && [ "$branch" != "(detached)" ]; then
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
    pr_cache="$cache_dir/pr-$(printf '%s' "$top@$branch" | tr -c 'A-Za-z0-9._-' '_')"
    if [ -z "$(find "$pr_cache" -mmin "-$(((${CLAUDE_STATUSLINE_PR_TTL:-60} + 59) / 60))" 2>/dev/null)" ]; then
      mkdir -p "$cache_dir" && touch "$pr_cache"
      (cd "$top" && review_lookup >"$pr_cache.tmp" 2>/dev/null
        mv "$pr_cache.tmp" "$pr_cache") </dev/null >/dev/null 2>&1 &
    fi
    seg "$PURPLE" "$DARK" "$(cat "$pr_cache" 2>/dev/null)"
  fi
fi
flush

# --- line 2: model and context ----------------------------------------------

seg "$GREY" "$LIGHT" "$model"
seg "$PURPLE" "$DARK" "${effort:+Thinking: $effort}"
if [ -n "$ctx_pct" ]; then
  width=16 filled=$(((ctx_pct * 16 + 50) / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  bar=$(printf "%${filled}s" "" | sed 's/ /█/g')$(printf "%$((width - filled))s" "" | sed 's/ /░/g')
  seg "$GREY" "$LIGHT" "[$bar] $ctx_tokens ($ctx_pct%)"
fi
if [ -f "$transcript" ]; then
  compactions=$(grep -c '"subtype":"compact_boundary"' "$transcript")
  [ "${compactions:-0}" -gt 0 ] && seg "$RED" "$DARK" "↻ $compactions"
fi
flush

# --- line 3: prompt cache and usage limits ----------------------------------

# Countdown from the last main-thread assistant reply that touched the cache.
# "live" while a turn is still running (a user entry newer than any reply).
if [ -f "$transcript" ]; then
  cache=$(tail -c 262144 "$transcript" | jq -Rnr --argjson ttl "${CLAUDE_STATUSLINE_CACHE_TTL:-3600}" '
    [inputs | try fromjson catch empty
      | select(.isSidechain != true and (.type == "assistant" or .type == "user"))] | reverse
    | if length == 0 then empty
      elif .[0].type == "user" then "live"
      else first(.[]
          | select(.type == "assistant" and .isApiErrorMessage != true and .timestamp != null)
          | select(.message.usage == null
                   or (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0) > 0)
          | ($ttl - 5 - (now - (.timestamp | sub("\\.[0-9]+"; "") | fromdate)))
          | if . <= 0 then "cold" else "\(. / 60 | floor):\(. % 60 | floor | tostring | if length < 2 then "0" + . else . end)" end)
      end' 2>/dev/null)
  seg "$GREY" "$LIGHT" "${cache:+Cache: $cache}"
fi
seg "$BLUE" "$DARK" "${five:+Session: $five}"
seg "$GREY" "$LIGHT" "${five_reset:+Reset: $five_reset}"
seg "$GREEN" "$DARK" "${week:+Weekly: $week}"
seg "$GREY" "$LIGHT" "${week_reset:+Weekly reset: $week_reset}"
flush
