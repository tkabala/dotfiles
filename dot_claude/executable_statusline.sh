#!/usr/bin/env bash
# Claude Code status line.
# Claude Code pipes session JSON on stdin and shows whatever this prints:
#   1: host · cwd · worktree · clean/dirty · branch · +/- lines · ahead/behind · PR
#   2: session name · time running · model · fast mode · thinking effort · context bar
#   3: prompt-cache countdown + hit ratio (or rebuild cost when cold) · cache misses · 5h usage + reset
#      · weekly usage + reset
# The context bar and usage pills turn amber at 50% and orange at 80%.
# Needs jq, git and a Nerd Font. The PR / MR comes from Claude Code's own lookup, which needs gh or glab
# logged in. Keep it bash 3.2-safe for macOS.

# Row widths are counted in characters, which needs a UTF-8 locale; sessions started over ssh or
# from a daemon can lack one, and then every icon counts as 3-4 columns and the right side drifts.
probe='░'
if [ "${#probe}" -ne 1 ]; then
  for LC_ALL in C.UTF-8 en_US.UTF-8; do [ "${#probe}" -eq 1 ] && break; done
  export LC_ALL
fi

input=$(cat)
command -v jq >/dev/null 2>&1 || { echo "statusline: jq not found"; exit 0; }

# --- session data -----------------------------------------------------------

# Everything the eval below sets, cleared first so a jq failure can't leave values from the environment.
cwd='' session_name='' worktree='' pr='' pr_url='' cache='' cache_miss='' model='' effort='' fast='' elapsed=''
ctx_pct='' ctx_tokens='' five='' five_reset='' week='' week_reset=''
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
              then $pc.expires_at - now | mmss
              else "cold" + ($pc.recache_tokens_if_cold | num
                | if . == null or . <= 0 then "" else " · \(kilo) to rebuild" end) end)
          + ($pc.hit_ratio | num | if . == null then "" else " · \(. * 100 | round)% hit" end)
        end)",
    @sh "cache_miss=\(($pc.misses | num // 0) as $n | if $n <= 0 then ""
        else "\($n) miss\(if $n > 1 then "es" else "" end)"
          + ($pc.last_miss_cause.causes // [] | if length > 0 then ": " + join(", ") else "" end)
        end)",
    @sh "model=\(.model | if type == "object" then .display_name // .id else . end // "")",
    @sh "effort=\(.effort.level // "")",
    @sh "fast=\(if .fast_mode == true then "fast" else "" end)",
    @sh "elapsed=\(.cost.total_duration_ms | num | if . == null then "" else . / 1000 | dur end)",
    @sh "ctx_pct=\($ctx_pct // "" | if . == "" then . else round end)",
    @sh "ctx_tokens=\(if $size == null then ""
                      else "\(($used // (($ctx_pct // 0) * $size / 100)) | kilo)/\($size | kilo)" end)",
    @sh "five=\($five)", @sh "five_reset=\($five_reset)",
    @sh "week=\($week)", @sh "week_reset=\($week_reset)"
' <<<"$input" 2>/dev/null)"
cwd=${cwd:-$PWD}

# --- lualine-style rendering ------------------------------------------------
# Rows span the full terminal width: segments queued with `L` hug the left edge, `R` the
# right edge, and the gap between is filled with the bar background. Colors are Tokyo Night
# hex values to match the starship prompt; an ANSI index (0-15) also works and follows the
# terminal's own color scheme instead.

RESET=$'\e[0m'
SEP=$'\xee\x82\xb4' CAP=$'\xee\x82\xb6'  # rounded powerline U+E0B4 / U+E0B6 (needs a Nerd font)
FADE='░▒▓'                               # shade blocks the left edge fades in through, as in the prompt
# color <38|48> <#rrggbb|index>: foreground (38) or background (48) escape.
color() {
  case $2 in
    \#*) printf '\e[%s;2;%d;%d;%dm' "$1" "0x${2:1:2}" "0x${2:3:2}" "0x${2:5:2}" ;;
    *) printf '\e[%s;5;%sm' "$1" "$2" ;;
  esac
}
fg() { color 38 "$1"; }
bg() { if [ "$1" = default ]; then printf '\e[49m'; else color 48 "$1"; fi; }

# Palette: Tokyo Night. BAR is the filler between the left and right groups: "default" keeps
# the terminal's own background; a color (e.g. #1f2335) paints it. Warnings are orange, like
# the prompt arrow after a failed command.
BAR=default DARK='#1a1b26' LIGHT='#c0caf5' GREY='#3b4261' BLUE='#7aa2f7' TEAL='#73daca'
GREEN='#9ece6a' AMBER='#e0af68' MAGENTA='#bb9af7' PURPLE='#9d7cd8' WARN='#ff9e64'
# Nerd Font icons (single-width, drawn in each pill's text color).
I_HOST=󰍹 I_DIR= I_TREE= I_BRANCH= I_PR=
I_SESSION=󰭹 I_CLOCK=󱎫 I_MODEL=󰚩 I_FAST=󱐋 I_THINK=󰧑 I_CTX=󰍛
I_CACHE=󰆼 I_WARN= I_HOURGLASS=󰔟 I_CAL=󰃭 I_RESET=󰑓
MARGIN=${STATUSLINE_MARGIN:-4}  # columns left unused: Claude Code truncates rows wider than its status area
# level <color> <percent>: the given color below 50%, amber below 80%, orange from there.
level() {
  local p=${2%%[.%]*}
  if [ "${p:-0}" -ge 80 ]; then echo "$WARN"; elif [ "${p:-0}" -ge 50 ]; then echo "$AMBER"; else echo "$1"; fi
}

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
    # The first pill fades in from the screen edge, like the prompt; later ones follow a separator.
    if [ -n "$prev" ]; then left+="$(fg "$prev")$(bg "${seg_bg[i]}")$SEP"; lw=$((lw + 1))
    else left+="$(fg "${seg_bg[i]}")$(bg "$BAR")$FADE"; lw=$((lw + 3)); fi
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

# Short hostname (up to the first dot), so sessions on other machines are easy to tell apart.
seg L "$GREY" "$LIGHT" "$I_HOST ${HOSTNAME%%.*}"
seg L "$BLUE" "$DARK" "$I_DIR ${cwd/#"$HOME"/\~}"

git_() { git -C "$cwd" --no-optional-locks "$@" 2>/dev/null; }

if status=$(git_ status --porcelain=v2 --branch); then
  branch=$(sed -n 's/^# branch\.head //p' <<<"$status")
  read -r ahead behind <<<"$(sed -n 's/^# branch\.ab +\([0-9]*\) -\([0-9]*\)$/\1 \2/p' <<<"$status")"
  shortstat=$(git_ diff --shortstat HEAD)
  added=$(sed -n 's/.* \([0-9]*\) insertion.*/\1/p' <<<"$shortstat")
  removed=$(sed -n 's/.* \([0-9]*\) deletion.*/\1/p' <<<"$shortstat")

  seg L "$TEAL" "$DARK" "${worktree:+$I_TREE $worktree}"
  if grep -qv '^#' <<<"$status"; then seg L "$GREY" "$LIGHT" "✗"; else seg L "$GREY" "$LIGHT" "✓"; fi
  seg L "$GREEN" "$DARK" "$I_BRANCH $branch"
  [ -n "$shortstat" ] && seg L "$AMBER" "$DARK" "+${added:-0} -${removed:-0}"
  ab=""
  [ "${ahead:-0}" -gt 0 ] && ab="↑$ahead"
  [ "${behind:-0}" -gt 0 ] && ab="${ab:+$ab }↓$behind"
  seg L "$MAGENTA" "$DARK" "$ab"
fi
# Open PR / MR for the branch, right-aligned, as an OSC 8 link when Claude Code knows its URL.
seg R "$PURPLE" "$DARK" "${pr:+$I_PR $pr}" "$pr_url"
flush

# --- line 2: model and context ----------------------------------------------

seg L "$LIGHT" "$DARK" "${session_name:+$I_SESSION $session_name}"
seg L "$TEAL" "$DARK" "${elapsed:+$I_CLOCK $elapsed}"
seg L "$GREY" "$LIGHT" "${model:+$I_MODEL $model}"
seg L "$AMBER" "$DARK" "${fast:+$I_FAST $fast}"
seg L "$PURPLE" "$DARK" "${effort:+$I_THINK $effort}"
if [ -n "$ctx_pct" ]; then
  width=16 filled=$(((ctx_pct * 16 + 50) / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  bar=$(printf "%${filled}s" "" | sed 's/ /█/g')$(printf "%$((width - filled))s" "" | sed 's/ /░/g')
  seg R "$(level "$GREEN" "$ctx_pct")" "$DARK" "$I_CTX $bar $ctx_tokens ($ctx_pct%)"
fi
flush

# --- line 3: prompt cache and usage limits ----------------------------------

seg L "$GREY" "$LIGHT" "${cache:+$I_CACHE $cache}"
seg L "$WARN" "$DARK" "${cache_miss:+$I_WARN $cache_miss}"
seg R "$(level "$BLUE" "$five")" "$DARK" "${five:+$I_HOURGLASS 5h $five}"
seg R "$GREY" "$LIGHT" "${five_reset:+$I_RESET $five_reset}"
seg R "$(level "$GREEN" "$week")" "$DARK" "${week:+$I_CAL 7d $week}"
seg R "$GREY" "$LIGHT" "${week_reset:+$I_RESET $week_reset}"
flush
