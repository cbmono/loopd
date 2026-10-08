// loopd-mod-usage — what this session spent, written to the plugin store after every turn
// under `loopd.usage.<session id>`, and `loopd.usage.<session id>.ended` at session end.
// Observe only: every hook hands the event on unchanged. It never calls a model, never
// decides a permission, never starts a process, never reaches the network or a file.
// tests/mods.test.sh in cbmono/loopd asserts those absences; README.md says why.

type Usage = {
  input_tokens?: unknown
  output_tokens?: unknown
  cache_read_input_tokens?: unknown
  cache_creation_input_tokens?: unknown
  model?: unknown
}

type Record = {
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
  requests: number
  turns: number
  ms: number
  model: string | null
  tools: { [name: string]: number }
  toolErrors: number
}

const acc: Record = {
  input: 0, output: 0, cacheRead: 0, cacheWrite: 0,
  requests: 0, turns: 0, ms: 0, model: null, tools: {}, toolErrors: 0,
}
// Request-level usage (turn.step results) is the primary source; the turn's own totals on
// turn.complete are the fallback for a turn whose steps carried none, never a second count.
let stepUsageThisTurn = false

function num(v: unknown): number {
  return typeof v === 'number' && isFinite(v) && v >= 0 ? Math.floor(v) : 0
}

function add(u: unknown): boolean {
  if (!u || typeof u !== 'object') return false
  const usage = u as Usage
  acc.input += num(usage.input_tokens)
  acc.output += num(usage.output_tokens)
  acc.cacheRead += num(usage.cache_read_input_tokens)
  acc.cacheWrite += num(usage.cache_creation_input_tokens)
  acc.requests += 1
  if (typeof usage.model === 'string' && usage.model) acc.model = usage.model
  return true
}

// Without a session id there is no key, and a record under a made-up key would be a
// number nothing can attribute — so nothing is written.
async function save($: any, ended: boolean, knownId?: unknown): Promise<void> {
  let id: unknown = typeof knownId === 'string' && knownId ? knownId : null
  if (!id) { try { id = await $.session.id() } catch { id = null } }
  if (typeof id !== 'string' || !id) return
  await $.store.set('loopd.usage.' + id, { ...acc, tools: { ...acc.tools } })
  if (ended) await $.store.set('loopd.usage.' + id + '.ended', true)
}

export function register(on: any) {
  on('session.start', async ($: any, e: any, next: any) => {
    // One line, and only where somebody can see it: a `claude -p` or `--bg` session has
    // no surface, and a line there would reach the transcript instead.
    if (e && e.isInteractive === true) {
      $.ui.log('recording this session\'s usage in the plugin store as loopd.usage.<session id>')
    }
    return next(e)
  })

  on('turn.step', async function* ($: any, e: any, next: any) {
    const result = yield* next(e)
    if (result && add(result.usage)) stepUsageThisTurn = true
    return result
  })

  // A gating hook: if this one throws, the call still goes through (fail open).
  on('tool.call', async ($: any, e: any, next: any) => {
    const result = await next(e)
    const name = e && typeof e.tool === 'string' && e.tool ? e.tool : 'unknown'
    acc.tools[name] = (acc.tools[name] || 0) + 1
    if (result && result.isError === true) acc.toolErrors += 1
    return result
  }).catch(($: any, e: any, next: any) => next(e))

  on('turn.complete', async ($: any, e: any, next: any) => {
    acc.turns += 1
    acc.ms += num(e ? e.durationMs : 0)
    if (!stepUsageThisTurn) add(e ? e.usage : null)
    stepUsageThisTurn = false
    await save($, false)
    return next(e)
  })

  // session.end carries the ending session's id itself (measured 2026-10-09, 2.1.293).
  on('session.end', async ($: any, e: any, next: any) => {
    await save($, true, e ? e.sessionId : null)
    return next(e)
  })
}
