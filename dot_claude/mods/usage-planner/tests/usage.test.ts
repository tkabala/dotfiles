import { expect, mock, test } from 'claude-code/testing'

import { learn, paceEstimate, turnEstimate } from '../hooks/register'

const ctx = { context: { contextWindowSize: 200000 } }
const FIVE_RESET = '2026-11-19T20:00:00Z'
const SEVEN_RESET = '2026-11-24T00:00:00Z'
const limits = (five: number, seven: number) => [
  { kind: 'five_hour', percentUsed: five, resetsAt: FIVE_RESET },
  { kind: 'seven_day', percentUsed: seven, resetsAt: SEVEN_RESET },
]
const at = (five: number, seven: number) => ({ ...ctx, changed: ['rateLimits'] as const, rateLimits: limits(five, seven) })
const NOW = Date.parse('2026-11-19T18:00:00Z')

test('warns once per threshold, highest crossed only', async ($, on) => {
  mock.store(on)
  mock.clock(on, { now: NOW })
  const session = mock.session(on)
  on('session.measure', (_, e) => ({ changed: e.changed }))

  await $.session.measure(at(40, 30) as never)
  expect(session.appended().length).toBe(0)

  await $.session.measure(at(83, 30) as never)
  const rows = session.appended()
  expect(rows.length).toBe(1)
  const text = JSON.stringify(rows[0]?.message.content)
  expect(text.includes('5-hour usage window is at 83%')).toBe(true)
  expect(text.includes('resets in 2h00m')).toBe(true)
  expect(text.includes('a turn is one user prompt')).toBe(true)

  await $.session.measure(at(85, 30) as never)
  expect(session.appended().length).toBe(1)

  await $.session.measure(at(91, 52) as never)
  expect(session.appended().length).toBe(2)
  const both = JSON.stringify(session.appended()[1]?.message.content)
  expect(both.includes('91%') && both.includes('weekly usage window is at 52%')).toBe(true)
})

test('the tool reports windows, the per-turn cost and the turn unit', async ($, on) => {
  mock.store(on, { burn: { five_hour: { avg: 2, n: 5 } } })
  mock.clock(on, { now: NOW })
  on('session.usage', () => ({ value: { startedAt: 0, ...at(40, 30) } }) as never)

  const r = await $.tool.call({ tool: 'mcp__usage-planner__usage_limits' } as never)
  const text = String((r as { result?: unknown }).result)
  expect(text.includes('5-hour window: 40% used, 60.0% left, resets in 2h00m')).toBe(true)
  expect(text.includes('about 2% per turn, so roughly 30 turns left')).toBe(true)
  expect(text.includes('weekly window: 30% used')).toBe(true)
  expect(text.includes('a turn is one user prompt with all its tool calls')).toBe(true)
})

test('the shown rate reproduces the count', async () => {
  expect(turnEstimate(11, { avg: 0.067, n: 10 })).toBe('about 0.07% per turn, so roughly 157 turns left')
  expect(turnEstimate(60, { avg: 1.89, n: 10 })).toBe('about 1.9% per turn, so roughly 31 turns left')
  expect(turnEstimate(60, { avg: 0.01, n: 10 })).toBe('under 0.05% per turn so far, so plenty of turns left')
  expect(turnEstimate(60, { avg: 3, n: 2 })).toBe('no per-turn estimate yet')
})

test('learning skips a window that reset and a reading that went down', async () => {
  const burn: Record<string, { avg: number; n: number }> = { five_hour: { avg: 1, n: 4 } }
  expect(learn(burn, limits(10, 50), limits(15, 51))).toBe(true)
  expect(burn.five_hour).toEqual({ avg: 1.8, n: 5 }) // 1 * 0.8 + 5 * 0.2
  expect(burn.seven_day).toEqual({ avg: 1, n: 1 })

  const reset: Record<string, { avg: number; n: number }> = { five_hour: { avg: 1, n: 4 } }
  const afterReset = [{ kind: 'five_hour', percentUsed: 2, resetsAt: '2026-11-20T01:00:00Z' }]
  expect(learn(reset, limits(90, 50), afterReset)).toBe(false)
  expect(learn(reset, limits(30, 50), limits(20, 50).slice(0, 1))).toBe(false)
  expect(reset.five_hour).toEqual({ avg: 1, n: 4 })
})

test('usage between turns counts with the next turn, but not after an idle gap', async ($, on) => {
  mock.store(on)
  const clock = mock.clock(on, { now: NOW })
  on('prompt.submit', (_, e) => ({ text: e.text }) as never)
  on('turn.complete', () => ({ text: '' }) as never)
  let reading = limits(10, 20)
  on('session.usage', () => ({ value: { startedAt: 0, ...ctx, rateLimits: reading } }) as never)

  await $.prompt.submit({ text: 'one' } as never)
  reading = limits(12, 20)
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'end_turn' } as never)

  // A background subagent spends 4 points before the next prompt, 5 minutes later.
  reading = limits(16, 20)
  await clock.advance(5 * 60_000)
  await $.prompt.submit({ text: 'two' } as never)
  reading = limits(17, 20)
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'end_turn' } as never)

  // An hour idle: what other sessions spent meanwhile is not this turn's.
  reading = limits(40, 20)
  await clock.advance(60 * 60_000)
  await $.prompt.submit({ text: 'three' } as never)
  reading = limits(41, 20)
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'end_turn' } as never)

  // Turns of 2, then 5 (4 between + 1), then 1: 2 -> 2.6 -> 2.28, shown as 2.3; 59 left.
  const r = await $.tool.call({ tool: 'mcp__usage-planner__usage_limits' } as never)
  expect(String((r as { result?: unknown }).result)).toContain('about 2.3% per turn, so roughly 25 turns left')
})

test('a subagent turn is not a main turn', async ($, on) => {
  mock.store(on)
  mock.clock(on, { now: NOW })
  on('prompt.submit', (_, e) => ({ text: e.text }) as never)
  on('turn.complete', () => ({ text: '' }) as never)
  on('session.usage', () => ({ value: { startedAt: 0, ...ctx, rateLimits: limits(10, 20) } }) as never)
  await $.prompt.submit({ text: 'one' } as never)
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'end_turn', agentId: 'a1' } as never)
  const r = await $.tool.call({ tool: 'mcp__usage-planner__usage_limits' } as never)
  expect(String((r as { result?: unknown }).result)).not.toContain('% per turn')
})

test('the pace says whether the window lasts until the reset', async () => {
  const first = { resetsAt: SEVEN_RESET, percent: 80, at: NOW }
  const later = NOW + 2 * 3_600_000
  const limit = { kind: 'seven_day', percentUsed: 84, resetsAt: SEVEN_RESET }
  // 2 points an hour, 16 left: about 8 hours; the reset is 4 days away.
  expect(paceEstimate(limit, first, later)).toBe(
    'at the pace since 2h00m ago (2.0%/h) it runs out in about 8h00m, before the reset',
  )
  const slow = { ...limit, percentUsed: 80.1 }
  expect(paceEstimate(slow, first, later)).toBe('at the pace since 2h00m ago (0.05%/h) it lasts past the reset')
  expect(paceEstimate(limit, first, NOW + 5 * 60_000)).toBe(null) // too short to tell
  expect(paceEstimate(limit, { ...first, resetsAt: 'other' }, later)).toBe(null)
})
