import { expect, test } from 'claude-code/testing'

// Run from this directory: `claude plugin test`. No session, no sign-in, no network.
// Each test starts with the module freshly loaded, so the accumulator is zero.

const SID = '0a1b2c3d-1111-2222-3333-444455556666'
const KEY = 'loopd.usage.' + SID
const STEP_USAGE = {
  input_tokens: 10, output_tokens: 5,
  cache_read_input_tokens: 1000, cache_creation_input_tokens: 100,
  model: 'claude-test',
}

// Every stub the mod's hooks can reach, registered before the first call on `$`.
function stubs(on: any, saved: Map<string, unknown>, logged: string[], sid: unknown = SID) {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.id', () => ({ value: sid }))
  on('ui.log', (_$: any, e: any) => { logged.push(e.text); return { value: undefined } })
  on('store.set', (_$: any, e: any) => { saved.set(e.key, e.value); return { value: undefined } })
  on('tool.call', (_$: any, e: any) => (e.tool === 'Bash' ? { result: 'exit 1', isError: true } : { result: 'ok' }))
  on('turn.start', (_$: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.end', () => ({}))
  on('turn.step', async function* (_$: any, e: any) {
    yield { kind: 'text', index: 0, text: 'ok' }
    return { turnId: e.turnId, index: e.index, answer: 'ok', toolUses: [], stopReason: 'end_turn', usage: STEP_USAGE }
  })
}

// One request to the model, read to the end of its stream.
async function step($: any, turnId: string, index: number) {
  const stream = $.turn.step({ turnId, index, model: 'claude-test', messageCount: 1 })
  let s = await stream.next()
  while (s.done !== true) s = await stream.next()
  return s.value
}

test('a turn\'s requests, tools, errors and wall time land in the store under the session id', async ($, on) => {
  const saved = new Map<string, unknown>()
  const logged: string[] = []
  stubs(on, saved, logged)

  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await $.tool.call({ tool: 'Bash', command: 'false' })
  await $.tool.call({ tool: 'Read', file_path: 'README.md' })
  await $.tool.call({ tool: 'Read', file_path: 'VERSION' })
  await step($, 't1', 0)
  await step($, 't1', 1)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1234, isAborted: false, usage: null })

  expect(saved.get(KEY)).toEqual({
    input: 20, output: 10, cacheRead: 2000, cacheWrite: 200,
    requests: 2, turns: 1, ms: 1234, model: 'claude-test',
    tools: { Bash: 1, Read: 2 }, toolErrors: 1,
  })
  // Not ended yet, and the one interactive line was logged exactly once.
  expect(saved.has(KEY + '.ended')).toBe(false)
  expect(logged.length).toBe(1)
})

test('a non-interactive session logs nothing and falls back to the turn\'s own totals', async ($, on) => {
  const saved = new Map<string, unknown>()
  const logged: string[] = []
  stubs(on, saved, logged)

  await $.session.start({ surface: 'terminal', isInteractive: false, cwd: '/work' })
  // No turn.step reached the mod, so turn.complete's usage is the only source.
  await $.turn.complete({
    turnId: 't1', answer: 'ok', durationMs: 500, isAborted: false,
    usage: { input_tokens: 7, output_tokens: 3, cache_read_input_tokens: 40, cache_creation_input_tokens: 0 },
  })

  expect(logged).toEqual([])
  expect(saved.get(KEY)).toMatchObject({ input: 7, output: 3, cacheRead: 40, cacheWrite: 0, requests: 1, turns: 1, ms: 500 })
})

test('turn totals are never added on top of the requests already counted', async ($, on) => {
  const saved = new Map<string, unknown>()
  stubs(on, saved, [])

  await step($, 't1', 0)
  await $.turn.complete({
    turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false,
    usage: { input_tokens: 999, output_tokens: 999, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
  })

  expect(saved.get(KEY)).toMatchObject({ input: 10, output: 5, requests: 1 })
})

test('the second turn accumulates onto the first', async ($, on) => {
  const saved = new Map<string, unknown>()
  stubs(on, saved, [])

  await step($, 't1', 0)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 100, isAborted: false, usage: null })
  await step($, 't2', 0)
  await $.turn.complete({ turnId: 't2', answer: 'ok', durationMs: 50, isAborted: true, usage: null })

  expect(saved.get(KEY)).toMatchObject({ input: 20, requests: 2, turns: 2, ms: 150 })
})

test('session.end marks the record ended and leaves the numbers', async ($, on) => {
  const saved = new Map<string, unknown>()
  stubs(on, saved, [])

  await step($, 't1', 0)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 10, isAborted: false, usage: null })
  await $.session.end({ reason: 'other' })

  expect(saved.get(KEY + '.ended')).toBe(true)
  expect(saved.get(KEY)).toMatchObject({ input: 10, requests: 1 })
})

test('without a session id nothing is written', async ($, on) => {
  const saved = new Map<string, unknown>()
  stubs(on, saved, [], undefined)

  await step($, 't1', 0)
  await $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 10, isAborted: false, usage: null })

  expect(saved.size).toBe(0)
})
