#!/usr/bin/env bash
# Claude Code subagent rows (the agent panel below the prompt), drawn as pills like the status line:
#   status + agent name · what it's doing · model + effort · context use (or tokens) + time running
# Context use turns amber at 50% and orange at 80%, like the main status line.
# Claude Code pipes {"columns": N, "tasks": [...]} on stdin and replaces each row whose id we
# print back as {"id": ..., "content": ...}. Needs jq and a Nerd Font.

command -v jq >/dev/null 2>&1 || exit 0

exec jq -c '
  # Tokyo Night, as "r;g;b" for 24-bit escapes; same palette as statusline.sh.
  {dark: "26;27;38", light: "192;202;245", grey: "59;66;97", blue: "122;162;247",
   green: "158;206;106", teal: "115;218;202", amber: "224;175;104", purple: "157;124;216", warn: "255;158;100",
   red: "247;118;142"} as $c
  | "" as $sep    # rounded powerline separator (U+E0B4)
  | def fg(x): "\u001b[38;2;\(x)m";
    def bg(x): "\u001b[48;2;\(x)m";
    def kilo: if . >= 999500 then "\(. / 100000 | round / 10)M"
      elif . >= 1000 then "\(. / 1000 | round)k" else "\(. | round)" end;
    def elapsed: floor as $s
      | if $s < 60 then "\($s)s"
        elif $s < 3600 then "\($s / 60 | floor)m \($s % 60)s"
        else "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m" end;
    # claude-opus-5-5 -> opus 5.5
    def model_name: sub("^claude-"; "") | sub("-(?<a>[0-9]+)-(?<b>[0-9]+)(-.*)?$"; " \(.a).\(.b)");
    def level(base): if . >= 80 then $c.warn elif . >= 50 then $c.amber else base end;
    # pills: [[bg, fg, text], ...] -> one row: flat start, rounded joins, rounded end.
    def render: . as $p
      | reduce range(0; $p | length) as $i ("";
          . + (if $i > 0 then fg($p[$i - 1][0]) + bg($p[$i][0]) + $sep else "" end)
            + bg($p[$i][0]) + fg($p[$i][1]) + " \($p[$i][2]) ")
      + fg($p[-1][0]) + "\u001b[49m" + $sep + "\u001b[0m";
    def width: map(.[2] | length + 2) | add + length;

  (.columns // 80) as $cols
  | .tasks[]
  | ({running: [$c.blue, "󰑮"], completed: [$c.green, ""], failed: [$c.red, ""],
      killed: [$c.grey, "󰜺"]}[.status] // [$c.grey, "•"]) as [$sc, $icon]
  | (if .contextWindowSize then (.tokenCount * 100 / .contextWindowSize | round) else null end) as $pct
  | [[$sc, $c.dark, "\($icon) \(.name // .agentType // "agent")"],
     (if .model then [$c.purple, $c.dark,
        (.model | model_name) + (if .effort then " · \(.effort)" else "" end)] else empty end),
     [($pct // 0 | level($c.teal)), $c.dark,
        (if $pct then "\($pct)%" else (.tokenCount | kilo) end)
        # Only start times are sent, so the clock is shown while the task runs.
        + (if .status == "running" then " · " + ((now - .startTime / 1000) | elapsed) else "" end)]
    ] as $fixed
  # The description pill gets whatever width is left, cut with an ellipsis if needed.
  | ($cols - ($fixed | width) - 4) as $room
  | (.label // .description // "") as $label
  | (if $room < 6 or $label == "" then null
     elif ($label | length) > $room then $label[:$room - 1] + "…" else $label end) as $text
  | {id, content: ([$fixed[0]] + (if $text then [[$c.grey, $c.light, $text]] else [] end)
                   + $fixed[1:] | render)}
'
