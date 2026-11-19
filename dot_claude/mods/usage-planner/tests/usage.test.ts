import { expect, mock, test } from 'claude-code/testing'

const ctx = { context: { contextWindowSize: 200000 } } as never
const at = (five: number, seven: number) => ({
  ...ctx,
  changed: ['rateLimits'] as const,
  rateLimits: [
    { kind: 'five_hour', percentUsed: five, resetsAt: '2026-11-19T20:00:00Z' },
    { kind: 'seven_day', percentUsed: seven, resetsAt: '2026-11-24T00:00:00Z' },
  ],
})

test('warns once per threshold, highest crossed only', async ($, on) => {
  mock.store(on)
  mock.clock(on, { now: Date.parse('2026-11-19T18:00:00Z') })
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

  await $.session.measure(at(85, 30) as never)
  expect(session.appended().length).toBe(1)

  await $.session.measure(at(91, 52) as never)
  expect(session.appended().length).toBe(2)
  const both = JSON.stringify(session.appended()[1]?.message.content)
  expect(both.includes('91%') && both.includes('weekly usage window is at 52%')).toBe(true)
})

test('the tool reports windows and the learned per-turn cost', async ($, on) => {
  mock.store(on, { burn: { five_hour: { avg: 2, n: 5 } } })
  mock.clock(on, { now: Date.parse('2026-11-19T18:00:00Z') })
  on('session.usage', () => ({ value: { startedAt: 0, ...at(40, 30) } }) as never)

  const r = await $.tool.call({ tool: 'mcp__usage-planner__usage_limits' } as never)
  const text = String((r as { result?: unknown }).result)
  expect(text.includes('5-hour window: 40% used, 60.0% left, resets in 2h00m')).toBe(true)
  expect(text.includes('roughly 30 turns left')).toBe(true)
  expect(text.includes('weekly window: 30% used')).toBe(true)
})
