#!/usr/bin/env bash
# Claude Code status line.
# Claude Code pipes session JSON on stdin and shows whatever this prints:
#   1: cwd · worktree · clean/dirty · branch · +/- lines · ahead/behind · PR
#   2: session name · model · thinking effort · context bar · compactions
#   3: prompt-cache countdown + hit ratio · cache misses · 5h usage + reset · weekly usage + reset
# Needs jq, git and a Nerd Font. The PR / MR comes from Claude Code's own lookup, which needs gh or glab
# logged in. Keep it bash 3.2-safe for macOS.

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
  def mmss: floor | "\(. / 60 | floor):\(. % 60 | tostring | if length < 2 then "0" + . else . end)";
  def pct: if . == null then "" else "\(. * 10 | round / 10)%" end;
  def kilo: if . >= 999500 then "\(. / 100000 | round / 10)M"
    elif . >= 1000 then "\(. / 1000 | round)k" else "\(. | round)" end;
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
  | (.prompt_cache // {}) as $pc
  | @sh "cwd=\(.workspace.current_dir // .cwd // "")",
    @sh "transcript=\(.transcript_path // "")",
    @sh "session_name=\(.session_name // "" | if length > 40 then .[:39] + "…" else . end)",
    @sh "worktree=\(.workspace.git_worktree // "")",
    @sh "pr=\(.pr // {} | if .number == null then "" else
        (if .kind == "mr" then "!" else "#" end) + "\(.number) "
        + if .review_state == "draft" then "draft"
          else "open" + ({approved: " ✓", changes_requested: " ✗", pending: " ?"}[.review_state // ""] // "") end
      end)",
    @sh "pr_url=\(.pr.url // "")",
    @sh "cache=\(if $pc.caching_observed != true then ""
        else (if $pc.warm == true and ($pc.expires_at | num) != null and $pc.expires_at > now
              then $pc.expires_at - now | mmss else "cold" end)
          + ($pc.hit_ratio | num | if . == null then "" else " · \(. * 100 | round)% hit" end)
        end)",
    @sh "cache_miss=\(($pc.misses | num // 0) as $n | if $n <= 0 then ""
        else "\($n) miss\(if $n > 1 then "es" else "" end)"
          + ($pc.last_miss_cause.causes // [] | if length > 0 then ": " + join(", ") else "" end)
        end)",
    @sh "model=\(.model | if type == "object" then .display_name // .id else . end // "")",
    @sh "effort=\(.effort.level // "")",
    @sh "ctx_pct=\($ctx_pct // "" | if . == "" then . else round end)",
    @sh "ctx_tokens=\(if $size == null then ""
                      else "\(($used // (($ctx_pct // 0) * $size / 100)) | kilo)/\($size | kilo)" end)",
    @sh "five=\($five)", @sh "five_reset=\($five_reset)",
    @sh "week=\($week)", @sh "week_reset=\($week_reset)"
' <<<"$input" 2>/dev/null)"
cwd=${cwd:-$PWD}

# --- lualine-style rendering ------------------------------------------------
# Rows span the full terminal width: segments queued with `L` hug the left edge, `R` the
# right edge, and the gap between is filled with the bar background. Colors are ANSI
# palette indices (0-15), not hex, so the terminal's color scheme themes the bar.

RESET=$'\e[0m'
SEP=$'\xee\x82\xb0' CAP=$'\xee\x82\xb2'  # powerline U+E0B0 / U+E0B2 (needs a powerline/Nerd font)
fg() { printf '\e[38;5;%sm' "$1"; }
bg() { if [ "$1" = default ]; then printf '\e[49m'; else printf '\e[48;5;%sm' "$1"; fi; }

# Palette: ANSI indices. BAR is the filler between the left and right groups: "default" keeps
# the terminal's own background; a number (e.g. 8 for a lighter grey bar) paints it.
BAR=default DARK=0 LIGHT=7 GREY=8 BLUE=4 ORANGE=3 GREEN=2 AMBER=11 PINK=5 PURPLE=13 RED=1 CYAN=6
# Nerd Font icons (single-width, drawn in each pill's text color).
I_DIR= I_TREE= I_BRANCH= I_PR=
I_SESSION=󰭹 I_MODEL=󰚩 I_THINK=󰧑 I_CTX=󰍛
I_CACHE=󰆼 I_WARN= I_HOURGLASS=󰔟 I_CAL=󰃭 I_RESET=󰑓
MARGIN=${STATUSLINE_MARGIN:-4}  # columns left unused: Claude Code truncates rows wider than its status area

# Terminal width: $COLUMNS, then the tty of this process or an ancestor (the status line
# runs without a controlling terminal), then tput; 120 as a last resort.
term_width() {
  local w=${COLUMNS:-} pid=$$ t
  if [ -z "$w" ]; then
    while [ "${pid:-0}" -gt 1 ]; do
      t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$t" ] && [ "$t" != "?" ] && [ "$t" != "??" ] && [ -r "/dev/${t#/dev/}" ]; then
        w=$(stty size <"/dev/${t#/dev/}" 2>/dev/null | cut -d' ' -f2)
        [ -n "$w" ] && break
      fi
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
  fi
  [ -n "$w" ] || w=$(tput cols 2>/dev/null)
  case $w in '' | *[!0-9]* | 0) w=120 ;; esac
  echo "$w"
}
WIDTH=$(term_width)

seg_side=() seg_bg=() seg_fg=() seg_text=() seg_url=()
# seg <L|R> <bg> <fg> <text> [url] — queue a segment; empty text skips it.
seg() {
  [ -n "$4" ] || return 0
  seg_side+=("$1") seg_bg+=("$2") seg_fg+=("$3") seg_text+=("$4") seg_url+=("${5:-}")
}
# Print the queued segments as one full-width row and start a new one.
flush() {
  local n=${#seg_text[@]} i body left="" right="" lw=0 rw=0 prev
  [ "$n" -gt 0 ] || return 0
  # Left group: each pill ends in a separator that blends into the next pill (or the bar).
  prev=""
  for ((i = 0; i < n; i++)); do
    [ "${seg_side[i]}" = L ] || continue
    body=${seg_text[i]}
    [ -n "${seg_url[i]}" ] && body=$'\e]8;;'"${seg_url[i]}"$'\e\\'"$body"$'\e]8;;\e\\'
    if [ -n "$prev" ]; then left+="$(fg "$prev")$(bg "${seg_bg[i]}")$SEP"; lw=$((lw + 1)); fi
    left+="$(bg "${seg_bg[i]}")$(fg "${seg_fg[i]}") $body "
    lw=$((lw + ${#seg_text[i]} + 2))
    prev=${seg_bg[i]}
  done
  [ -n "$prev" ] && { left+="$(fg "$prev")$(bg "$BAR")$SEP"; lw=$((lw + 1)); }
  # Right group: each pill starts with a cap that blends from the previous pill (or the bar).
  prev=$BAR
  for ((i = 0; i < n; i++)); do
    [ "${seg_side[i]}" = R ] || continue
    body=${seg_text[i]}
    [ -n "${seg_url[i]}" ] && body=$'\e]8;;'"${seg_url[i]}"$'\e\\'"$body"$'\e]8;;\e\\'
    right+="$(fg "${seg_bg[i]}")$(bg "$prev")$CAP$(bg "${seg_bg[i]}")$(fg "${seg_fg[i]}") $body "
    rw=$((rw + ${#seg_text[i]} + 3))
    prev=${seg_bg[i]}
  done
  local gap=$((WIDTH - MARGIN - lw - rw))
  [ "$gap" -lt 1 ] && gap=1
  printf '%s%s%*s%s%s\n' "$left" "$(bg "$BAR")" "$gap" "" "$right" "$RESET"
  seg_side=() seg_bg=() seg_fg=() seg_text=() seg_url=()
}

# --- line 1: location and git -----------------------------------------------

seg L "$BLUE" "$DARK" "$I_DIR ${cwd/#"$HOME"/\~}"

git_() { git -C "$cwd" --no-optional-locks "$@" 2>/dev/null; }

if status=$(git_ status --porcelain=v2 --branch); then
  branch=$(sed -n 's/^# branch\.head //p' <<<"$status")
  read -r ahead behind <<<"$(sed -n 's/^# branch\.ab +\([0-9]*\) -\([0-9]*\)$/\1 \2/p' <<<"$status")"
  shortstat=$(git_ diff --shortstat HEAD)
  added=$(sed -n 's/.* \([0-9]*\) insertion.*/\1/p' <<<"$shortstat")
  removed=$(sed -n 's/.* \([0-9]*\) deletion.*/\1/p' <<<"$shortstat")

  seg L "$ORANGE" "$DARK" "${worktree:+$I_TREE $worktree}"
  if grep -qv '^#' <<<"$status"; then seg L "$GREY" "$LIGHT" "✗"; else seg L "$GREY" "$LIGHT" "✓"; fi
  seg L "$GREEN" "$DARK" "$I_BRANCH $branch"
  [ -n "$shortstat" ] && seg L "$AMBER" "$DARK" "+${added:-0} -${removed:-0}"
  ab=""
  [ "${ahead:-0}" -gt 0 ] && ab="↑$ahead"
  [ "${behind:-0}" -gt 0 ] && ab="${ab:+$ab }↓$behind"
  seg L "$PINK" "$DARK" "$ab"
fi
# Open PR / MR for the branch, right-aligned, as an OSC 8 link when Claude Code knows its URL.
seg R "$PURPLE" "$DARK" "${pr:+$I_PR $pr}" "$pr_url"
flush

# --- line 2: model and context ----------------------------------------------

seg L "$LIGHT" "$DARK" "${session_name:+$I_SESSION $session_name}"
seg L "$GREY" "$LIGHT" "${model:+$I_MODEL $model}"
seg L "$PURPLE" "$DARK" "${effort:+$I_THINK $effort}"
if [ -n "$ctx_pct" ]; then
  width=16 filled=$(((ctx_pct * 16 + 50) / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  bar=$(printf "%${filled}s" "" | sed 's/ /█/g')$(printf "%$((width - filled))s" "" | sed 's/ /░/g')
  seg R "$GREY" "$LIGHT" "$I_CTX $bar $ctx_tokens ($ctx_pct%)"
fi
if [ -f "$transcript" ]; then
  compactions=$(grep -c '"subtype":"compact_boundary"' "$transcript")
  [ "${compactions:-0}" -gt 0 ] && seg R "$RED" "$DARK" "↻ $compactions"
fi
flush

# --- line 3: prompt cache and usage limits ----------------------------------

seg L "$GREY" "$LIGHT" "${cache:+$I_CACHE $cache}"
seg L "$RED" "$DARK" "${cache_miss:+$I_WARN $cache_miss}"
seg R "$BLUE" "$DARK" "${five:+$I_HOURGLASS 5h $five}"
seg R "$GREY" "$LIGHT" "${five_reset:+$I_RESET $five_reset}"
seg R "$GREEN" "$DARK" "${week:+$I_CAL 7d $week}"
seg R "$GREY" "$LIGHT" "${week_reset:+$I_RESET $week_reset}"
flush
