// Throwaway probe. Records, for every event it hooks, the event's field names and the
// fields that matter to a usage mod, under a store key that names the event and the
// session. Nothing else.
let seq = 0

function summary(e) {
  const out = { keys: Object.keys(e || {}) }
  if (e && e.usage !== undefined) out.usage = e.usage
  if (e && e.model !== undefined) out.model = e.model
  if (e && e.durationMs !== undefined) out.durationMs = e.durationMs
  if (e && e.isAborted !== undefined) out.isAborted = e.isAborted
  if (e && e.reason !== undefined) out.reason = e.reason
  if (e && e.tool !== undefined) out.tool = e.tool
  if (e && e.agentId !== undefined) out.agentId = e.agentId
  if (e && e.surface !== undefined) out.surface = e.surface
  if (e && e.isInteractive !== undefined) out.isInteractive = e.isInteractive
  return out
}

async function record($, name, e, extra) {
  let sid = 'nosid'
  try { sid = await $.session.id() } catch (err) { sid = 'err:' + String(err && err.message) }
  seq += 1
  const key = 'probe.' + sid + '.' + String(seq).padStart(3, '0') + '.' + name
  const value = { ...summary(e), at: Date.now(), ...(extra || {}) }
  await $.store.set(key, value)
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    let surfaces = null
    try { surfaces = await $.session.surfaces() } catch (err) { surfaces = 'err:' + String(err && err.message) }
    await record($, 'session.start', e, { surfaces })
    try {
      await $.command.register({ name: 'probe-dump', description: 'dump the probe store', immediate: true })
    } catch (err) {}
    return next(e)
  })

  on('command.run', { command: 'probe-dump' }, async ($) => {
    const keys = await $.store.keys()
    const lines = []
    for (const k of keys) {
      const v = await $.store.get(k)
      lines.push(k + ' ' + JSON.stringify(v))
    }
    return { text: lines.join('\n') || '(store empty)' }
  })

  on('turn.start', async ($, e, next) => {
    await record($, 'turn.start', e)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    await record($, 'turn.step', e, { resultKeys: Object.keys(result || {}), resultUsage: result ? result.usage : null, resultModel: result ? result.model : null, stopReason: result ? result.stopReason : null })
    return result
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    await record($, 'tool.call', e, { resultKeys: Object.keys(result || {}), isError: result ? result.isError : null, deny: result ? result.deny : null })
    return result
  })

  on('turn.complete', async ($, e, next) => {
    await record($, 'turn.complete', e)
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await record($, 'session.measure', e)
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    await record($, 'session.end', e)
    return next(e)
  })
}
