// loopd-mod-signal — a role agent's session tells the project-manager's session that its
// turn is over, the moment it is over, instead of step 4 finding out at the next tick.
//
// ONE MODULE, TWO SIDES, told apart by the working directory and nothing else:
//
//   · the PM side runs in a bundle root (`<cwd>/instance.config.json` exists). At
//     session.start it writes `loopd.pm.<bundle root>` = { sessionId, at } to the plugin
//     store, so a role agent of that bundle can find the session to tell. Newest wins;
//     a stale entry costs nothing, because a send to a gone session is `isDelivered: false`.
//   · the role side runs in a linked worktree of a repo `link-repos.sh` marked. At every
//     turn.complete of the MAIN loop it resolves the bundle the way the plugin's
//     deny-destructive.sh guard does — `<cwd>/.git` is a FILE naming the gitdir, the gitdir's
//     `commondir` names the common dir, `<common>/loopd-bundle` names the bundle, and the
//     bundle must hold `instance.config.json` — writes `loopd.signal.<session id>` to the
//     store (the durable half, readable whether or not any message lands), and sends the PM
//     session ONE line. Every step that fails ends the hook silently: a main clone (`.git` a
//     directory), a repo with no marker, a marker naming nothing — each is "not a role
//     agent", the same absence-is-silence rule the deny hook keeps (docs/conventions.md §19).
//
// `turn.complete` is the end-of-work moment, not `session.end`: a `claude --bg` session stays
// alive and idle after its brief is answered and never fires session.end (measured
// 2026-10-09 on 2.1.293, docs/spikes/mods-in-background-sessions.md). A subagent's turn
// fires turn.complete too, with `agentId` set — an Explore child of a role agent is not the
// role agent finishing, so those are skipped.
//
// THE LINE ORDERS STEP 4 AND DECIDES NOTHING. Nothing here reads a task document, decides a
// status, submits a prompt or consumes a message: `check-dispatch.sh` is report-only because
// a checker that acted on its own reading would automate the loop's most expensive failure
// (plugin/seed/CONVENTIONS.md), and a signal that advanced a task would be that checker. The
// `session.receive` hook below passes every message through unchanged; it exists so the
// pass-through is stated and tested, not implied.
//
// WHAT IT READS, exactly (README.md → "What it reads", asserted by tests/mods.test.sh in
// cbmono/loopd): `instance.config.json` under the cwd and under the marker's target, `.git`
// under the cwd (stat, then read), the gitdir's `commondir`, and `loopd-bundle` in the common
// dir. Nothing else, and never a write.
//
// NEVER: a model call, a hook on the permission event, a process, the network, the
// environment, a file write, a walk up from the cwd — tests/mods.test.sh asserts each
// absence on this source, so none of those is spelled here even as a call.

const CONFIG = 'instance.config.json'
const GIT = '.git'
const COMMONDIR = 'commondir'
const MARKER = 'loopd-bundle'
const PM_KEY = 'loopd.pm.'
const SIGNAL_KEY = 'loopd.signal.'
const PREFIX = 'loopd-signal:'
// After this many undelivered sends in one session the role side stops sending and keeps
// writing the store: a session that refuses or holds inbound messages is not spammed, and
// step 4 still has the record.
const MAX_FAILED_SENDS = 2

// Module state. A reload starts it over; the store is the durable copy.
let turns = 0
let failedSends = 0

// ---------------------------------------------------------------- small, guarded helpers
function str(v: unknown): string { return typeof v === 'string' ? v : '' }
function num(v: unknown): number { return typeof v === 'number' && isFinite(v) && v >= 0 ? Math.floor(v) : 0 }
// The one line the PM reads must stay one line: a path is a filename, and a filename may
// carry a newline or an ESC on this platform (docs/conventions.md §12). Control characters
// become one space; nothing else is touched.
function oneLine(s: string): string { return s.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim() }
// The first line of a small file, trimmed — what `IFS= read -r` gives the deny hook.
function firstLine(v: unknown): string { return str(v).split('\n')[0].replace(/\r$/, '').trim() }

// Lexical join + normalise: `base/rel` with `.` and `..` folded, no symlink resolved, so a
// relative `gitdir:` or `commondir` (git writes `../..`) lands on the path git means.
function join(base: string, rel: string): string {
  const p = rel.startsWith('/') ? rel : base.replace(/\/+$/, '') + '/' + rel
  const out: string[] = []
  for (const part of p.split('/')) {
    if (part === '' || part === '.') continue
    if (part === '..') { out.pop(); continue }
    out.push(part)
  }
  return '/' + out.join('/')
}

async function cwdOf($: any): Promise<string> {
  let cwd: unknown = null
  try { cwd = await $.session.cwd() } catch { cwd = null }
  const s = str(cwd).replace(/\/+$/, '')
  return s.startsWith('/') ? s : ''
}
async function exists($: any, path: string): Promise<boolean> {
  try { return (await $.fs.exists(path)) === true } catch { return false }
}
async function read($: any, path: string): Promise<string> {
  try { return firstLine(await $.fs.read(path)) } catch { return '' }
}
async function sessionId($: any): Promise<string> {
  let id: unknown = null
  try { id = await $.session.id() } catch { id = null }
  return str(id)
}

// The bundle a role agent's worktree belongs to, or '' — the deny hook's walk, read for read.
async function bundleOf($: any, cwd: string): Promise<string> {
  let st: any = null
  try { st = await $.fs.stat(cwd + '/' + GIT) } catch { st = null }
  if (!st || st.kind !== 'file') return ''          // a main clone, or no repo: not a role agent
  let gitdir = read_gitdir(await read($, cwd + '/' + GIT))
  if (!gitdir) return ''
  gitdir = join(cwd, gitdir)
  const common = await read($, gitdir + '/' + COMMONDIR)
  const commonDir = common ? join(gitdir, common) : gitdir
  const bundle = await read($, commonDir + '/' + MARKER)
  if (!bundle || !bundle.startsWith('/')) return ''
  const root = join('/', bundle)
  if (!(await exists($, root + '/' + CONFIG))) return ''   // a marker naming nothing: silence
  return root
}
function read_gitdir(line: string): string {
  if (!line.startsWith('gitdir:')) return ''
  return line.slice('gitdir:'.length).trim()
}

// ---------------------------------------------------------------- hooks
export function register(on: any) {
  // PM side: a session that starts in a bundle root is that bundle's PM for as long as it
  // is the newest one written. Anywhere else this hook only hands the event on.
  on('session.start', async ($: any, e: any, next: any) => {
    const cwd = await cwdOf($)
    if (cwd && await exists($, cwd + '/' + CONFIG)) {
      const sid = await sessionId($)
      if (sid) await $.store.set(PM_KEY + cwd, { sessionId: sid, at: new Date().toISOString() })
    }
    return next(e)
  }).catch(($: any, e: any, next: any) => next(e))

  // Role side: the main loop's turn ended in a marked worktree ⇒ record it, then say so once.
  on('turn.complete', async ($: any, e: any, next: any) => {
    if (e && typeof e.agentId === 'string' && e.agentId) return next(e)   // a subagent's turn
    turns += 1
    const cwd = await cwdOf($)
    if (!cwd || await exists($, cwd + '/' + CONFIG)) return next(e)      // the PM, or no cwd
    const bundle = await bundleOf($, cwd)
    if (!bundle) return next(e)
    const sid = await sessionId($)
    if (!sid) return next(e)        // no id ⇒ no key ⇒ nothing anyone could attribute

    const reason = str(e ? e.reason : '') || 'unknown'
    const record = {
      bundle, cwd, at: new Date().toISOString(), turns,
      durationMs: num(e ? e.durationMs : 0), reason,
      isAborted: !!(e && e.isAborted === true),
      delivered: null as boolean | null,
    }
    await $.store.set(SIGNAL_KEY + sid, record)       // the durable half, before any message

    if (failedSends >= MAX_FAILED_SENDS) return next(e)
    let pm: any = null
    try { pm = await $.store.get(PM_KEY + bundle) } catch { pm = null }
    const to = pm && typeof pm === 'object' ? str(pm.sessionId) : ''
    if (!to || to === sid) return next(e)

    const text = oneLine(PREFIX + ' role session ' + sid + ' finished a turn in ' + cwd
      + ' (reason ' + reason + ', ' + record.durationMs + ' ms) — settle it first at step 4 of a /loopd:dispatch tick; this line orders the sweep and decides nothing')
    let delivered = false
    try {
      const sent = await $.session.send({ to: { sessionId: to }, text })
      delivered = !!(sent && sent.isDelivered === true)
    } catch { delivered = false }
    if (!delivered) failedSends += 1
    await $.store.set(SIGNAL_KEY + sid, { ...record, delivered })
    return next(e)
  }).catch(($: any, e: any, next: any) => next(e))

  // PM side, receive: a `loopd-signal:` line — and every other message — goes through to
  // Claude unchanged. Not consumed, no prompt submitted, no file touched: the tick decides.
  on('session.receive', async (_$: any, e: any, next: any) => {
    return next(e)
  }).catch(($: any, e: any, next: any) => next(e))
}
