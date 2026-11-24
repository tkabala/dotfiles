import type { AgentInfo, EngineInterface, Register } from 'claude-code'

// ── Main session ────────────────────────────────────────────────────────────
// The cache TTL counts from the start of the last request, and a turn ends a bit
// after that, so 50 min after the turn ends leaves a margin under the hour.
const DELAY_MS = 50 * 60 * 1000
// Stop after this many keepalives with no prompt from you, so a session you left
// open doesn't run up cost forever (3 pings = about 2.5 hours of cover).
const MAX_UNATTENDED_PINGS = 3
const PROMPT =
  "Keepalive check (automatic, sent after 50 min idle): what's the status of the task? " +
  'If something is still running in the background, check on it briefly and say whether it looks hung. ' +
  'If nothing is pending, reply in one line.'

// ── Subagents ───────────────────────────────────────────────────────────────
const POLL_MS = 20 * 1000
// Statuses an agent can be woken from by a message. A busy (running) agent only
// queues the message until its tool returns, which doesn't help its cache.
// idle: a teammate between turns. waiting: a subagent that ended its turn and is
// held on background work it owns. (A finished subagent drops out of the list.)
const WARM_STATUSES = new Set<string>(['idle', 'waiting'])
// Keep warming one agent for at most this long without a prompt from you.
const MAX_WARM_SPAN_MS = 30 * 60 * 1000
// A notification this soon after a warm, for that agent, is the warm's echo.
const ECHO_WINDOW_MS = 3 * 60 * 1000
const WARM_TEXT =
  'Automatic cache keepalive from the cache-keepalive mod. No action needed: reply with just "ok".'

const ttlMs = (ttl: '5m' | '1h') => (ttl === '1h' ? 3_600_000 : 300_000)
// Warm this long before expiry: 90 s for a 5 min cache, 10 min for a 1 h one.
const marginMs = (ttl: '5m' | '1h') => (ttl === '1h' ? 600_000 : 90_000)

// Module state; a reload starts it over (session.start re-arms everything).
let timer: { cancel: () => void } | undefined
let poller: { cancel: () => void } | undefined
let pings = 0
let dueAt = 0
let enabled = true
// Busy agents already warned about, per request (`<id>:<at>`), so each warns once.
const warned = new Set<string>()
const warms = new Map<string, { count: number; firstAt: number; lastAt: number; lastResult: string }>()

function hhmm(ms: number) {
  return new Date(ms).toTimeString().slice(0, 8)
}

function mins(ms: number) {
  const s = Math.round(ms / 1000)
  return `${s < 0 ? '-' : ''}${Math.floor(Math.abs(s) / 60)}m${String(Math.abs(s) % 60).padStart(2, '0')}s`
}

function cancelTimer() {
  timer?.cancel()
  timer = undefined
}

async function arm($: EngineInterface) {
  cancelTimer()
  if (!enabled || pings >= MAX_UNATTENDED_PINGS) return
  dueAt = (await $.clock.now()) + DELAY_MS
  timer = $.clock.after(DELAY_MS, () => {
    timer = undefined
    pings++
    void $.prompt.submit({ text: PROMPT })
  })
}

// A warmed agent going back to waiting notifies the main session, which would
// cost a main turn per warm. This spots that echo; real results don't match.
function isWarmEcho(text: string, now: number) {
  if (!text.includes('toolu_plugin_') || !text.includes('is waiting on its own background work')) return false
  for (const [id, w] of warms) {
    if (text.includes(`<task-id>${id}</task-id>`) && now - w.lastAt < ECHO_WINDOW_MS) return true
  }
  return false
}

function describe(a: AgentInfo, now: number) {
  const r = a.lastRequest
  const w = warms.get(a.id)
  const cache = r?.cacheTtl ? `ttl ${r.cacheTtl}, left ${mins(r.at + ttlMs(r.cacheTtl) - now)}` : 'no cache info'
  const warm = w ? `, warmed ${w.count}x (last ${hhmm(w.lastAt)}: ${w.lastResult})` : ''
  return `  ${a.name ?? a.description} [${a.id}] ${a.status}, ${cache}${warm}`
}

async function pollAgents($: EngineInterface) {
  if (!enabled) return
  const now = await $.clock.now()
  for (const a of await $.agent.list()) {
    const r = a.lastRequest
    if (!r?.cacheTtl) continue
    const left = r.at + ttlMs(r.cacheTtl) - now
    // A busy agent can't be warmed: say once when its cache runs out mid-run,
    // the sign of a long foreground command or a hang.
    if (a.status === 'running' && left <= 0 && !warned.has(`${a.id}:${r.at}`)) {
      warned.add(`${a.id}:${r.at}`)
      $.ui.toast(`${a.name ?? a.description}: ${r.cacheTtl} cache expired mid-run (busy ${mins(now - r.at)}); long command or hung?`)
    }
    if (!WARM_STATUSES.has(a.status)) continue
    if (left <= 0 || left > marginMs(r.cacheTtl)) continue
    const w = warms.get(a.id) ?? { count: 0, firstAt: now, lastAt: 0, lastResult: '' }
    if (now - w.firstAt > MAX_WARM_SPAN_MS) continue
    // Don't send twice for the same request while the first warm is in flight.
    if (w.lastAt > r.at) continue
    w.count++
    w.lastAt = now
    try {
      const sent = await $.session.send({ to: { agentId: a.id }, text: WARM_TEXT })
      w.lastResult = sent.isDelivered ? 'delivered' : `refused: ${sent.reason}`
    } catch (err) {
      w.lastResult = `error: ${String(err)}`
    }
    warms.set(a.id, w)
  }
}

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'keepalive', description: 'Cache keepalive: on | off | status' })
    await arm($)
    poller?.cancel()
    poller = $.clock.every(POLL_MS, () => void pollAgents($))
    return next(e)
  })

  on('command.run', { command: 'keepalive' }, async ($, e) => {
    const arg = String(e.args ?? '').trim()
    if (arg === 'off') { enabled = false; cancelTimer(); return { text: 'Keepalive off.' } }
    if (arg === 'on') { enabled = true; pings = 0; warms.clear(); await arm($); return { text: `Keepalive on, fires at ${hhmm(dueAt)}.` } }
    const now = await $.clock.now()
    const agents = await $.agent.list()
    const lines = [
      `Keepalive ${enabled ? 'on' : 'off'}, ${timer ? `armed, fires at ${hhmm(dueAt)}` : 'idle'}, ${pings}/${MAX_UNATTENDED_PINGS} unattended pings used.`,
      agents.length ? 'Agents:' : 'No subagents.',
      ...agents.map(a => describe(a, now)),
    ]
    return { text: lines.join('\n') }
  })

  // Real activity resets the unattended budgets: a prompt you typed (terminal or
  // phone), a background task or subagent waking the main session, or a /loop or
  // scheduled task firing. Our own keepalive prompt (origin 'plugin') doesn't.
  on('prompt.submit', async ($, e, next) => {
    const kind = e.origin?.kind
    // Dropping it prints one dim line; task notifications don't pass session.receive.
    // Checked first, so a warm's echo never counts as activity.
    if (kind === 'task-notification' && isWarmEcho(e.text, await $.clock.now())) return { drop: '' }
    if (kind === 'composer' || kind === 'bridge' || kind === 'task-notification' || kind === 'scheduled-trigger') {
      pings = 0
      warms.clear()
    }
    cancelTimer()
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    // Only the main session's turns: a subagent's (e.g. a warm's "ok") has agentId.
    if (!e.agentId) await arm($)
    return result
  })
}
