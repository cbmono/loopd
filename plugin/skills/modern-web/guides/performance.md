<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/performance/ (26 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Performance

Open for: LCP/INP/CLS, fetch priority, long tasks, `content-visibility`, lazy media, speculation rules, beacons, visibility state, A/B flicker, caching.

## Critical rendering path
- Inline above-the-fold CSS in `<head>`; defer the rest via `<link rel="preload" as="style" onload="this.onload=null;this.rel='stylesheet'">` + `<noscript>`.
- `defer` for DOM-dependent/ordered scripts, `async` for independent; `type="module"` defers by default. No big JS in `<head>`. Never `@import`.
- `media=` on `<link>` (print, desktop-only) downloads without blocking.
- `preconnect` known third-party origins; `dns-prefetch` as lean fallback; `preload` same-origin viewport assets; `prefetch` next-page assets.
- Third-party scripts: `defer`, end of `<body>`; self-host critical ones. Code-split with dynamic `import()`; chunk vendors.

## LCP and fetch priority
- LCP image in raw HTML: `<img>` preferred; `<link rel="preload" as="image">` only when CSS/JS owns it. No JS hero loaders.
- `fetchpriority="high"` on the LCP `<img>` and its preload; 1–2 per page max (zero-sum). Never with `loading="lazy"`.
- `fetchpriority="low"` for above-the-fold-but-hidden images (carousel slides, mega menus), optionally with `loading="lazy"`; never on ordinary below-fold lazy images.
- Below-fold images, iframes, media: `loading="lazy"` alone; never on the LCP image. Omit the attribute for default priority (not `auto`); `importance` and `loading="auto"` work nowhere.
- Preloads take the type's default priority (images: low): `fetchpriority="high"` on LCP image preloads, `low` on non-critical early ones; max 2 image + 2–3 font preloads; correct `as`/`type`.
- Fonts are high priority already — never `fetchpriority="high"`; font preloads always `crossorigin` (even same-origin); preload above-the-fold fonts only; subset.
- Scripts: `fetchpriority="high"` only on 1–2 INP-critical `async` scripts; `low` (+ `async`/`defer`/module) on analytics, ads, widgets, late-body scripts.
- `fetch(url, { priority: 'low' })` for analytics, telemetry, speculative data; the key is `priority`, not `importance`.
- Support: Baseline Newly available (since 2024-10-29): Chrome 103, Edge 103, Firefox 132, Safari 17.2; ignored elsewhere.

## Images and media
- `<picture>`: AVIF/JPEG XL, then WebP, then JPEG/PNG. `width`/`height` on every `<img>`. `srcset` always with `sizes` (else `100vw` assumed).
- Decorative CSS images: `image-set()` in `background-image`, `mask-image` or pseudo-element `content`, best format first with `type()` and `1x`/`2x`, a plain `url()` before it as fallback. Not for LCP candidates — the preload scanner can't see CSS images.
- Support (`image-set()`): Baseline Widely available (since 2023-09-18): Chrome 113, Edge 113, Firefox 89, Safari 17.
- `<video>`: integer `width`/`height`, `poster`, `preload="none"` when non-critical, WebM + MP4, captions `<track>`; preload the poster `as="image" fetchpriority="high"` when the video is the LCP. Don't autoplay large files.
- `loading="lazy"` on below-fold `<video>`/`<audio>` defers poster, `preload` and `autoplay`. Unloaded video is 300×150: size it or it may never intersect and never load; lazy `<audio>` needs `controls` or never loads. `window` `load` ignores lazy media; needs JS. Honour `prefers-reduced-motion` before autoplay.
- Support (lazy media): Limited — Chrome 150, Edge 150; not Firefox/Safari; others obey `preload` (poster eager). Strict fallback: `Object.hasOwn(HTMLMediaElement.prototype, 'loading')`, else `IntersectionObserver` swapping in `data-poster`/`data-src`, then `media.load()`.

## INP and long tasks
- 50 ms rule: under 50 ms run sync; 50–250 ms slice and yield; over 250 ms Web Worker. Yield on a time budget, not an iteration count:

```js
let deadline = performance.now() + 50;
for (const item of items) {
  processItem(item);
  if (performance.now() >= deadline) {
    await ('scheduler' in window && 'yield' in scheduler ? scheduler.yield() : new Promise(r => setTimeout(r, 0)));
    deadline = performance.now() + 50;
  }
}
```

- `scheduler.yield()` resumes at the front of the queue; `setTimeout(…, 0)` at the back — fallback only.
- `scheduler.postTask(fn, { priority })`: `user-blocking` (input), `user-visible` (default), `background` (analytics, prefetch). Feature-detect `'postTask' in scheduler`, else `scheduler-polyfill`.
- Support (Scheduler API): Limited — Chrome 129, Edge 129, Firefox 142; not Safari; fallback mandatory.
- Debounce/throttle `scroll`, `resize`, rapid `input`; no heavy `setInterval`; batch DOM reads (`offsetHeight`, `getBoundingClientRect`) before writes; paint feedback sync, compute in a worker.
- Heavy scroll work in `scrollend` (fires once scroll, snap and touch rest), not a debounced `scroll`.
- Support (`scrollend`): Baseline Newly available (since 2025-12-12): Chrome 114, Edge 114, Firefox 109, Safari 26.2; fallback `'onscrollend' in window`, else debounce `scroll` 100 ms and dispatch `new CustomEvent('scrollend')`.

## Field diagnostics
- Split INP into subparts: input delay (other JS), processing duration (handlers), presentation delay (rendering); fix the right one.
- `web-vitals/attribution` `onINP()`; beacon the subparts, `interactionTarget`, `longestScript.entry.{invokerType,sourceURL,sourceFunctionName,sourceCharPosition}` and `.subpart` via `navigator.sendBeacon`.
- `long-animation-frame` entries (`buffered: true`): group `scripts[]` by `sourceURL`, sum `duration`, sort descending; cheaper than JS Self-Profiling.
- `forcedStyleDuration`/`forcedLayoutDuration` (in-script) and `styleDuration`/`layoutDuration` (rendering) tell selectors/invalidation from geometry/thrashing; fallbacks `forcedStyleAndLayoutDuration`, `attribution.totalStyleAndLayoutDuration`.
- Support: event timing Baseline Newly available (since 2025-12-12): Chrome 76, Edge 79, Firefox 89, Safari 26.2; LoAF Limited — Chrome 123, Edge 123; not Firefox/Safari.

## content-visibility
- `content-visibility: auto` on large self-contained blocks strictly below the fold. Never above the fold; skip on small simple pages.
- Always pair with `contain-intrinsic-size` (`auto <length>`; `none` per axis) or off-screen height collapses to 0 and the scrollbar jumps; derive from content in `rem`/`lh`/`ch`, e.g. `auto calc(1lh + .4rem + .85lh)`.
- Verify keyboard reachability; nodes stay in the a11y tree — manage `aria-hidden` yourself.
- On-screen it still implies `contain: layout style paint`, so a mutation in one Kanban column reflows only that column; fallback `@supports not (content-visibility: auto) { contain: layout style paint }`.
- `content-visibility: hidden` for toggled views caches render state (re-shows faster than `display: none`) but drops content from the a11y tree and find-in-page (need find-in-page: `hidden="until-found"`, see css.md); the box still paints — `position: absolute` to leave flow. Dynamic routes need LRU eviction (RAM); focus the new view. Fallback `display: none` + `@supports (content-visibility: hidden) { display: block; content-visibility: hidden }`.
- `contentvisibilityautostatechange` (`event.skipped`) pauses/resumes canvas, WebGL, polling at the pre-render margin; may not bubble — listen on the element or `{ capture: true }`. Fallback: `'contentVisibility' in document.documentElement.style`, else `IntersectionObserver`, `rootMargin: '200px'`.
- `will-change` only on the element animating now, never globally.
- Support: Baseline Newly available (since 2025-09-15): Chrome 108, Edge 108, Firefox 130, Safari 26; ignored otherwise, so `hidden` needs the fallback.

## Next-page loading (speculation rules)
- `<script type="speculationrules">` JSON. Start with `prefetch`; `prerender` when the developer asks. MPAs only — useless in SPAs.
- Prefer document rules (`where: { href_matches, selector_matches, and, not }`) over `urls` lists. `eagerness`: `immediate` (very few links), `eager`, `moderate` (hover), `conservative` (pointerdown); non-eager cap at 2. Mix `prefetch` eager + `prerender` moderate.
- Exclude state-changing URLs (`/logout`, `add-to-cart`, `[rel~=nofollow]`); care on dynamic pages (staleness, cost). `tag` surfaces in `Sec-Speculation-Tags`.
- Support: Limited — Chrome 109, Edge 109; not Firefox/Safari.

## Caching
- Service worker: `NetworkFirst` HTML, `CacheFirst` hashed assets, `StaleWhileRevalidate` tolerant API data; cap entries/age; never `CacheFirst` opaque (no-CORS) responses; no POST caching (background sync); version assets.
- `Cache-Control: no-store` blocks bfcache — private data only; `no-cache`/`max-age=0` for fresh pages.

## Conditional polyfills (top-level await)
- Feature-detect on the prototype (`'popover' in HTMLElement.prototype`), then `await import('/polyfill.js')` at module top level; consumers `import` that module.
- TLA suspends only its importer, not siblings: never `import './polyfill.js'; import './app.js';` — chain `await import('./polyfill.js'); await import('./app.js');`; one importer only (Safari 15–26.6 breaks on concurrent imports).
- Support: Baseline Newly available (since 2026-09-14): Chrome 89, Edge 89, Firefox 89, Safari 27 (basic since 2021, Safari 15); pre-2021: wrap in an async function.

## Analytics beacons
- `fetchLater(url, { method, headers, body, signal, activateAfter })` for anything needing no response: sent after `activateAfter` or when the user leaves. Never an `<img>` pixel in `unload` (unreliable, kills bfcache).
- Update: `abort()` the pending controller, re-call with the full snapshot; batch by re-calling with the event queue, reset once `result.activated`, cap its size.
- Quota about 64 KB per origin — `try/catch`; no `ReadableStream` body. Feature-detect on `globalThis`.
- Polyfill (`globalThis.fetchLater ??=`): sends on `visibilitychange` to hidden or after `activateAfter` via `fetch(…, { keepalive: true })` or `navigator.sendBeacon`; app code calls only `fetchLater()`.
- Support: Limited — Chrome 135, Edge 135; not Firefox/Safari.

## Visibility state
- `performance.getEntriesByType('visibility-state')` (`name` `visible`/`hidden`, `startTime`): first entry `hidden` = loaded in background, exclude from load metrics; foreground time = sum of visible periods, the last ending at `performance.now()`. `document.visibilityState` at script time races.
- Support: Limited — Chrome 115, Edge 115; not Firefox/Safari. Empty array = unsupported: return `performance.now()`, or fall back to `document.visibilityState` + `visibilitychange` (imprecise).

## Flicker-free client-side A/B
- Experiment script in `<head>` with `async` + `blocking="render"` (external) or `type="module" blocking="render"` (inline): parsing continues, paint waits. `<head>` only; never on non-visual scripts; never with a legacy anti-flicker snippet.
- Keep it under 100 ms; set `document.documentElement.dataset.variant`, style via `[data-variant="b"]`; load tracking separately. No developer timeout — a CDN outage blocks paint; prefer server-side testing. Dynamic variant stylesheets also get `blocking="render"`.
- Support: Limited — Chrome 105, Edge 105, Safari 18.2; not Firefox. Fallback when `!Object.hasOwn(HTMLScriptElement.prototype, 'blocking')`: `.ab-loading { opacity: 0 !important }`, reveal after 4 s or when the SDK is ready.
