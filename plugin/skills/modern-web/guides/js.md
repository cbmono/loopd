<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/js/ (5 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# JavaScript: dates, times and calendars

Open for: date, time, duration, time-zone, DST or calendar logic.

## Temporal basics
- Use `Temporal`, not `Date`; `Date` is epoch ms with no calendar or zone math.
- Support: Limited — Chrome 144 (Jan 2026), Edge 144 (Jan 2026), Firefox 139 (May 2025); unsupported in Safari. Feature-detect and dynamically import `temporal-polyfill` (~15 KB min+gz); it does not set `globalThis.Temporal`:

```js
if (typeof Temporal === 'undefined') {
  const m = await import('temporal-polyfill');
  globalThis.Temporal = m.Temporal;
  Date.prototype.toTemporalInstant = m.toTemporalInstant;
}
```

- Immutable: `.add()`, `.subtract()`, `.round()`, `.with()`, `.withTimeZone()` return a new instance.
- Zones by IANA id (`Europe/Berlin`), never a fixed offset — offsets change with DST and legislation.
- Never interpolate ISO strings from parts; chain: `Temporal.PlainDate.from(d).toPlainDateTime(t).toZonedDateTime(tz)`.
- `Instant`/`ZonedDateTime` = a physical moment (logs, cross-zone scheduling); `Plain*` = calendar/wall-clock values that must not shift with location.
- Display via `.toLocaleString(locale, options)`, never hand-pad or concatenate; `.toString()` is ISO 8601 for machines (APIs, `<time datetime>`).
- `PlainTime` as `HH:MM` (`<input type="time">`): `.toString({ smallestUnit: 'minute' })`, not `.slice(0, 5)`.
- Compare with `.equals()` or static `Type.compare(a, b)`, never `.toString()` or field-by-field; read `.year`/`.month`/`.day` off a Plain type, not `Intl.DateTimeFormat.formatToParts()`.
- `Date` interop: out via `plainDate.toZonedDateTime('UTC').toInstant().epochMilliseconds` → `new Date(ms)` (document the zone); in via `date.toTemporalInstant()` or `Temporal.Instant.fromEpochMilliseconds(date.getTime())`, then `.toZonedDateTimeISO(tz).toPlainDate()` — the date depends on `tz`. Never `new Date(d + 'T00:00:00Z')`.

## Plain types: location-agnostic data
- `PlainDate` birthdates, billing dates · `PlainTime` alarms, opening hours · `PlainDateTime` floating local schedule · `PlainMonthDay` annual dates · `PlainYearMonth` card expiry, billing periods. Pick the narrowest so placeholder days never leak into arithmetic.
- A `Date` for `"1990-01-01"` is midnight UTC; west of UTC it reads 1989-12-31. Use `PlainDate`.
- Pass `calendar: 'iso8601'` when building `PlainMonthDay`/`PlainYearMonth` from property bags or any non-ISO type; ISO strings and `PlainDate.from({ year, month, day })` default to it.
- No arithmetic on `PlainMonthDay`; first `.toPlainDate({ year })` (February varies by year). "Is today": `monthDay.equals(today.toPlainMonthDay())`.
- Expiry: `Temporal.PlainYearMonth.compare(expiry, today.toPlainYearMonth()) < 0`.
- `plainDate.add({ months: 1 })` defaults to `{ overflow: 'constrain' }` (Jan 31 → Feb 28/29); `{ overflow: 'reject' }` throws `RangeError` instead.

## Zoned events and DST
- `Temporal.ZonedDateTime` for anything bound to a place; never `PlainDateTime` — it cannot account for DST.
- Build: `Temporal.ZonedDateTime.from('2025-03-09T02:30[America/New_York]', { disambiguation })`.
- `disambiguation: 'reject'` throws `RangeError` when DST skips or repeats the wall-clock time — detect and warn; `'compatible'` (default) picks a sensible valid time.
- Other location: `.withTimeZone('Asia/Tokyo')`, then `.toLocaleString(locale, { hour: 'numeric', minute: '2-digit' })`.

## Differentials and durations
- `Temporal.Now.zonedDateTimeISO(tz?)` — pass an IANA zone when the event's zone differs from the system's.
- `now.since(start, opts)` elapsed, `now.until(end, opts)` remaining — both return `Temporal.Duration`. Never `Date`/`.getTime()` arithmetic.
- `ZonedDateTime` differences default to `largestUnit: 'hour'` (days vary across DST): pass `'day'`/`'week'`/`'month'`/`'year'` for a human breakdown, `smallestUnit: 'minute'` to drop sub-minute noise.
- Standalone: `Temporal.Duration.from({ minutes: 90 }).round({ largestUnit: 'hour' })` → 1 h 30 min; pass `relativeTo` when balancing across months, years or DST.
- `Temporal.Duration.compare(d1, d2, { relativeTo })` — `relativeTo` (`PlainDate` or `ZonedDateTime`) is required when either duration has `years`/`months`/`weeks` or crosses DST.
- Expired: `duration.sign < 0` (or `Temporal.ZonedDateTime.compare()`).
- Display: `duration.toLocaleString(locale, { style })` or `new Intl.DurationFormat(locale, { style })`, style `'long' | 'short' | 'narrow' | 'digital'`; never `${d.years}y ${d.months}m`. `duration.toString()` → `PT1H30M`, machines only.
- Support (`Intl.DurationFormat`): Baseline Newly available (since 2025-03-04) — Chrome 129 (Sep 2024), Edge 129 (Sep 2024), Firefox 136 (Mar 2025), Safari 16.4 (Mar 2023).

## High-precision timestamps
- `new Date(ts)`/`Date.parse()` truncate to ms, so ns timestamps collide and sort unstably; parse with `Temporal.Instant.from(iso)` — exact UTC point, full ns, no zone.
- Keep the source's timestamp: browsers clamp `Temporal.Now.instant()` to ms/µs (Spectre). Local sub-ms timing: `performance.now()`/`performance.mark()`.
- Sort: `items.toSorted((a, b) => Temporal.Instant.compare(a.ts, b.ts))`. Equality: `a.equals(b)`, not `compare() === 0`.
- Gap: `curr.since(prev)` → `Duration`, shown via `.toLocaleString(locale, { style: 'narrow' })`. Not `duration.total('nanoseconds')` — a `Number`, unsafe past ~104 days; `epochNanoseconds` (`BigInt`) math is exact but loses units.
- Serialize with `instant.toString()` (UTC, `Z`); local wall-clock via `instant.toZonedDateTimeISO(tz)`.

## Non-ISO calendars
- Check first: `Intl.supportedValuesOf('calendar').includes(id)` in try/catch; fall back to ISO and warn when `date.calendar.id !== id`.
- `plainDate.withCalendar('hebrew')` before any calendar-sensitive operation.
- Lunisolar calendars (Hebrew, Chinese) have leap months: identify months by `monthCode`, not numeric `month`; `inLeapYear` may mean a whole extra month.
- Never assume 12 months or 31 days: loop to `date.monthsInYear`, read `date.with({ month: m }).daysInMonth`; last month is `month === monthsInYear`.
- Compare with `Temporal.PlainDate.compare()`, not year/month/day fields.
- Display: `toLocaleString('en-u-ca-hebrew', { day: 'numeric', month: 'long', year: 'numeric', era: 'long' })`; include `era` for era-based calendars (Japanese, Buddhist).
- Islamic-calendar variants are observation-based; `Intl` approximates — verify critical religious dates with domain experts or a specialized library.
