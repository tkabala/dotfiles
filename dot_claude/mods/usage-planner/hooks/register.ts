import type { Register, SessionRateLimit } from 'claude-code'

// Warn the agent (and toast the person) when a window first crosses each level.
const THRESHOLDS: Record<string, number[]> = {
  five_hour: [60, 80, 90],
  seven_day: [50, 75, 90],
}

const LABEL: Record<string, string> = { five_hour: '5h', seven_day: '7d' }
const label = (kind: string) => LABEL[kind] ?? kind

// Per-kind running average of how many percentage points one main-thread turn uses.
type Burn = Record<string, { avg: number; n: number }>
// Per-kind highest threshold already warned about, for the window that resets at `resetsAt`.
type Warned = Record<string, { resetsAt: string; level: number }>

const ALPHA = 0.2 // weight of the newest turn in the running average

function untilReset(resetsAt: string | undefined, now: number): string {
  if (!resetsAt) return 'unknown'
  const mins = Math.max(0, Math.round((Date.parse(resetsAt) - now) / 60000))
  const d = Math.floor(mins / 1440)
  const h = Math.floor((mins % 1440) / 60)
  const m = mins % 60
  return d > 0 ? `${d}d${h}h` : h > 0 ? `${h}h${String(m).padStart(2, '0')}m` : `${m}m`
}

export const register: Register = on => {
  let turnStart: SessionRateLimit[] | null = null

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    $.ui.status(undefined) // clear the status line an earlier version pinned
    await $.tool.register({
      name: 'usage_limits',
      isDeferred: false,
      description:
        "Reports the Claude subscription's usage-limit windows: the 5-hour window and the weekly (7-day) window, " +
        'each with percent used, time until it resets, the average percent one turn has been using, and an ' +
        'estimate of turns left. Call it before planning multi-step work, starting a long task, or spawning ' +
        'subagents, and size the plan to what is left: finish or checkpoint work before a window runs out, ' +
        'and put the most important steps first. Figures come from the last API response, so they lag by one request.',
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
    const lines = rateLimits.map(l => {
      const b = burn[l.kind]
      const left = Math.max(0, 100 - l.percentUsed)
      let est = 'no per-turn estimate yet'
      if (b && b.n >= 3) {
        est =
          b.avg > 0.05
            ? `about ${b.avg.toFixed(1)}% per turn, so roughly ${Math.floor(left / b.avg)} turns left`
            : `under 0.1% per turn so far, so plenty of turns left`
      }
      return `- ${l.kind === 'five_hour' ? '5-hour window' : l.kind === 'seven_day' ? 'weekly window' : l.kind}: ` +
        `${l.percentUsed}% used, ${left.toFixed(1)}% left, resets in ${untilReset(l.resetsAt, now)}` +
        (l.resetsAt ? ` (${l.resetsAt})` : '') + `; ${est}.`
    })
    return { result: `Usage limits (estimates; one subagent run can cost several turns' worth):\n${lines.join('\n')}` }
  })

  on('prompt.submit', async ($, e, next) => {
    turnStart = (await $.session.usage()).rateLimits
    return next(e)
  })

  // Learn how much one main-thread turn costs.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && turnStart && turnStart.length > 0) {
      const { rateLimits } = await $.session.usage()
      const burn = ((await $.store.get('burn')) ?? {}) as Burn
      let changed = false
      for (const l of rateLimits) {
        const before = turnStart.find(s => s.kind === l.kind)
        if (!before || before.resetsAt !== l.resetsAt) continue // the window reset mid-turn
        const delta = l.percentUsed - before.percentUsed
        if (delta < 0) continue
        const b = burn[l.kind]
        burn[l.kind] = b ? { avg: b.avg * (1 - ALPHA) + delta * ALPHA, n: b.n + 1 } : { avg: delta, n: 1 }
        changed = true
      }
      if (changed) await $.store.set('burn', burn)
    }
    turnStart = null
    return result
  })

  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    if (!e.changed.includes('rateLimits')) return result
    const now = await $.clock.now()

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
      const advice =
        crossed >= 90
          ? 'Finish or checkpoint the current task now; do not start new large work or subagents.'
          : crossed >= 75
            ? 'Prefer finishing the current task over starting new ones; avoid subagents unless needed.'
            : 'Keep plans lean and put the most important steps first.'
      notes.push(`${name} usage window is at ${l.percentUsed}%, resets in ${untilReset(l.resetsAt, now)}. ${advice}`)
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
