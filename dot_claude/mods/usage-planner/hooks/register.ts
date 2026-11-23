import type { Register, SessionRateLimit } from 'claude-code'

// Warn the agent (and toast the person) when a window first crosses each level.
const THRESHOLDS: Record<string, number[]> = {
  five_hour: [60, 80, 90],
  seven_day: [50, 75, 90],
}

// Per-kind running average of how many percentage points one main-loop turn uses.
type Burn = Record<string, { avg: number; n: number }>
// Per-kind highest threshold already warned about, for the window that resets at `resetsAt`.
type Warned = Record<string, { resetsAt: string; level: number }>
// Per-kind first reading seen in the current window, for the pace across all sessions.
type Pace = Record<string, { resetsAt: string; percent: number; at: number }>
type Reading = { limits: SessionRateLimit[]; at: number }

const ALPHA = 0.2 // weight of the newest turn in the running average
const MIN_TURNS = 3 // turns measured before an estimate is shown
const NEGLIGIBLE = 0.05 // percentage points per turn below which no count is given
// Usage between the end of one turn and the next prompt (background subagents,
// notifications) is counted with the next turn, unless the gap is this long:
// then it is mostly other sessions on the same account, not this one.
const IDLE_GAP_MS = 30 * 60_000
const MIN_PACE_MS = 15 * 60_000 // observed span before a pace per hour is shown

const windowName = (kind: string) =>
  kind === 'five_hour' ? '5-hour window' : kind === 'seven_day' ? 'weekly window' : kind

function duration(ms: number): string {
  const mins = Math.max(0, Math.round(ms / 60000))
  const d = Math.floor(mins / 1440)
  const h = Math.floor((mins % 1440) / 60)
  const m = mins % 60
  return d > 0 ? `${d}d${h}h` : h > 0 ? `${h}h${String(m).padStart(2, '0')}m` : `${m}m`
}

function untilReset(resetsAt: string | undefined, now: number): string {
  return resetsAt ? duration(Date.parse(resetsAt) - now) : 'unknown'
}

/** One decimal for one point or more, two below, so the shown rate reproduces the count. */
const points = (value: number) => value.toFixed(value >= 1 ? 1 : 2)

/** The per-turn estimate for a window. */
export function turnEstimate(left: number, burn: { avg: number; n: number } | undefined): string {
  if (!burn || burn.n < MIN_TURNS) return 'no per-turn estimate yet'
  if (burn.avg < NEGLIGIBLE) return `under ${NEGLIGIBLE}% per turn so far, so plenty of turns left`
  const rate = Number(points(burn.avg))
  return `about ${rate}% per turn, so roughly ${Math.floor(left / rate)} turns left`
}

/** The pace since the window was first seen, and whether it lasts until the reset. */
export function paceEstimate(limit: SessionRateLimit, first: Pace[string] | undefined, now: number): string | null {
  if (!first || !limit.resetsAt || first.resetsAt !== limit.resetsAt) return null
  const span = now - first.at
  const used = limit.percentUsed - first.percent
  if (span < MIN_PACE_MS || used <= 0) return null
  const perHour = used / (span / 3_600_000)
  const left = Math.max(0, 100 - limit.percentUsed)
  const lasts = (left / perHour) * 3_600_000
  const reset = Date.parse(limit.resetsAt) - now
  return (
    `at the pace since ${duration(span)} ago (${points(perHour)}%/h) it ` +
    (lasts >= reset ? `lasts past the reset` : `runs out in about ${duration(lasts)}, before the reset`)
  )
}

/** The running averages after one turn that went from `before` to `after`. */
export function learn(burn: Burn, before: SessionRateLimit[], after: SessionRateLimit[]): boolean {
  let changed = false
  for (const l of after) {
    const start = before.find(s => s.kind === l.kind)
    if (!start || start.resetsAt !== l.resetsAt) continue // the window reset in between
    const delta = l.percentUsed - start.percentUsed
    if (delta < 0) continue
    const b = burn[l.kind]
    burn[l.kind] = b ? { avg: b.avg * (1 - ALPHA) + delta * ALPHA, n: b.n + 1 } : { avg: delta, n: 1 }
    changed = true
  }
  return changed
}

export const register: Register = on => {
  let turnStart: SessionRateLimit[] | null = null
  let lastEnd: Reading | null = null

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    $.ui.status(undefined) // clear the status line an earlier version pinned
    await $.tool.register({
      name: 'usage_limits',
      isDeferred: false,
      description:
        "Reports the Claude subscription's usage-limit windows: the 5-hour window and the weekly (7-day) window, " +
        'each with percent used, time until it resets, the pace per hour across all sessions with whether it ' +
        'lasts until the reset, and the average percent one turn uses with an estimate of turns left. A turn is ' +
        'one user prompt and the whole response to it, all its tool calls included, not one tool call. Call it ' +
        'before planning multi-step work, starting a long task, or spawning subagents, and size the plan in ' +
        'turns: finish or checkpoint work before a window runs out, and put the most important steps first. ' +
        'Figures come from the last API response, so they lag by one request.',
      inputSchema: { type: 'object', properties: {} },
    })
    return result
  })

  on('tool.run', { tool: 'mcp__usage-planner__usage_limits' }, async ($, e, next) => {
    const { rateLimits } = await $.session.usage()
    const now = await $.clock.now()
    if (rateLimits.length === 0) {
      return { result: 'No usage-limit reading yet (none until the first API response of the session, or not on a subscription plan).' }
    }
    const burn = ((await $.store.get('burn')) ?? {}) as Burn
    const pace = ((await $.store.get('pace')) ?? {}) as Pace
    const lines = rateLimits.map(l => {
      const left = Math.max(0, 100 - l.percentUsed)
      const parts = [
        `${l.percentUsed}% used, ${left.toFixed(1)}% left, resets in ${untilReset(l.resetsAt, now)}` +
          (l.resetsAt ? ` (${l.resetsAt})` : ''),
        paceEstimate(l, pace[l.kind], now),
        turnEstimate(left, burn[l.kind]),
      ]
      return `- ${windowName(l.kind)}: ${parts.filter(Boolean).join('; ')}.`
    })
    return {
      result:
        `Usage limits (estimates; a turn is one user prompt with all its tool calls; ` +
        `a subagent run can cost several turns' worth):\n${lines.join('\n')}`,
    }
  })

  on('prompt.submit', async ($, e, next) => {
    const now = await $.clock.now()
    // Count from the last turn's end, so background work in between is not lost.
    turnStart =
      lastEnd && now - lastEnd.at <= IDLE_GAP_MS ? lastEnd.limits : (await $.session.usage()).rateLimits
    return next(e)
  })

  // Learn how much one main-loop turn costs.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId !== undefined) return result
    const { rateLimits } = await $.session.usage()
    if (turnStart && turnStart.length > 0 && rateLimits.length > 0) {
      const burn = ((await $.store.get('burn')) ?? {}) as Burn
      if (learn(burn, turnStart, rateLimits)) await $.store.set('burn', burn)
    }
    lastEnd = { limits: rateLimits, at: await $.clock.now() }
    turnStart = null
    return result
  })

  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    if (!e.changed.includes('rateLimits')) return result
    const now = await $.clock.now()

    // The first reading of each window period, for the pace across sessions.
    const pace = ((await $.store.get('pace')) ?? {}) as Pace
    let paceChanged = false
    for (const l of e.rateLimits) {
      const resetsAt = l.resetsAt ?? ''
      if (pace[l.kind]?.resetsAt !== resetsAt) {
        pace[l.kind] = { resetsAt, percent: l.percentUsed, at: now }
        paceChanged = true
      }
    }
    if (paceChanged) await $.store.set('pace', pace)

    const burn = ((await $.store.get('burn')) ?? {}) as Burn
    const warned = ((await $.store.get('warned')) ?? {}) as Warned
    const notes: string[] = []
    for (const l of e.rateLimits) {
      const levels = THRESHOLDS[l.kind]
      if (!levels) continue
      const resetsAt = l.resetsAt ?? ''
      const prev = warned[l.kind]
      const prevLevel = prev && prev.resetsAt === resetsAt ? prev.level : 0
      const crossed = levels.filter(t => l.percentUsed >= t && t > prevLevel).pop()
      if (crossed === undefined) continue
      warned[l.kind] = { resetsAt, level: crossed }
      const name = l.kind === 'five_hour' ? '5-hour' : 'weekly'
      const left = Math.max(0, 100 - l.percentUsed)
      const estimate = turnEstimate(left, burn[l.kind])
      const advice =
        crossed >= 90
          ? 'Put the most important remaining steps first and checkpoint as you go; size new work by the turns left.'
          : crossed >= 75
            ? 'Prefer finishing the current task over starting new ones; avoid subagents unless needed.'
            : 'Keep plans lean and put the most important steps first.'
      notes.push(
        `${name} usage window is at ${l.percentUsed}%, resets in ${untilReset(l.resetsAt, now)}; ` +
          `${estimate} (a turn is one user prompt with all its tool calls). ${advice}`,
      )
      $.ui.toast(`${name} usage at ${l.percentUsed}% (resets in ${untilReset(l.resetsAt, now)})`)
    }
    if (notes.length > 0) {
      await $.store.set('warned', warned)
      await $.session.append({
        message: { type: 'user', content: [{ type: 'text', text: `Usage limits: ${notes.join(' ')}` }] },
      })
    }
    return result
  })
}
