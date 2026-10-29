<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/ui-behaviors/ (37 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# UI behaviours: motion, transitions, dialogs, scroll, gestures
Open for: animations, view transitions, dialogs/popovers/tooltips, scroll-driven and snap effects, drag/swipe, text highlights, DOM moves.

## Motion basics
- Animate only `opacity`, `transform` or `translate`/`scale`/`rotate` (compositor); never `left/top`, `width/height`. `clip-path`/`mask-image` for reveals.
- Reduced motion: nest `@media (prefers-reduced-motion: reduce)` in each rule (or opt in under `no-preference`); no global `animation-duration: 0.01ms`. Pausable auto-running carousels; no flashing above 3/s.
- Animation/transition events: `event.animation` is the exact `Animation`; `getAnimations().find()` is unreliable.
- Springs/bounces: generator-made `linear(0, 1.116 5.4%, …, 1)` stops in a custom property; fixed duration required; no bounce on `opacity`; a prior `transition-timing-function` is the fallback. Support: Baseline Widely available (since 2023-12-11).
- Stagger: `animation-delay: calc(sibling-index() * .1s)`; fallback: JS sets `--sibling-index`, read by a `var()` declaration placed before the `sibling-index()` one. Support: Baseline Newly available (since 2026-08-18).

## Entry/exit animation
- Entry = `@starting-style` inside/after the open-state selector (first style update skips transitions otherwise). Exit = the transition back to the hidden state, never `@starting-style`.
- Transitioning `display` needs a separate `transition-behavior: allow-discrete` after the shorthand (inside it, old browsers drop the declaration). Top layer (`<dialog>`, `[popover]`, `::backdrop`) must also transition `overlay` or it drops out mid-exit.

```css
dialog, [popover] { opacity: 0; transition: opacity .3s, display .3s, overlay .3s; transition-behavior: allow-discrete; }
dialog[open], [popover]:popover-open { opacity: 1; @starting-style { opacity: 0; } }
```

- Removal: set `hidden`, await `Promise.allSettled(el.getAnimations().map(a => a.finished))` with a timeout, then `remove()`.
- Firefox parses `allow-discrete` but won't transition `display` (bug 1882408): probe a temp element's computed `display`, not `CSS.supports`. Fallback: a `[data-closing]` state with the exit styles, await `getAnimations()`, then `hidden`/`close()`/`hidePopover()`.
- Support: `@starting-style`, `transition-behavior` Baseline Newly available (since 2024-08-06); `overlay` Limited — Chrome/Edge 117+ only; discrete `display` Limited — Chrome/Edge 117+, Safari 18+, not Firefox.

## View transitions
- `document.startViewTransition(() => updateDOM())`, else `updateDOM()`. Support: Baseline Newly available (since 2025-10-14).
- `view-transition-name` unique per state or the transition is skipped. List→detail: set `hero.style.viewTransitionName` to the clicked item's name; clear temporary names in `transition.finished`.
- Focus is not managed: focus the new heading (`tabindex="-1"`) after `finished`. Reduced motion: `::view-transition-group(*), ::view-transition-old(*), ::view-transition-new(*) { animation: none !important }`.
- Direction: `startViewTransition({ update, types: ['forward'] })` + `html:active-view-transition-type(forward)::view-transition-old(root)`. Support: Baseline Newly available (since 2026-01-13).
- Lists: `view-transition-class: item` → `::view-transition-group(.item)`; added/removed = `::view-transition-new(.item):only-child` / `-old(.item):only-child`. Stay interactive: `::view-transition { pointer-events: none }`, `:root { view-transition-name: none }`. Support: Baseline Newly available (since 2025-10-14).
- Scoped: `el.startViewTransition()` keeps the page interactive and `position: fixed`/popovers on top. `view-transition-name: match-element` tracks node identity (move, don't rebuild); `view-transition-scope: all` hides a component's names from outer transitions; `transition.ready.catch(() => {})` on re-trigger. Detect `'startViewTransition' in Element.prototype`. Support: Limited — Chrome/Edge 147+ only.
- Cross-document: `@view-transition { navigation: auto }` on both pages (`navigation: none` under reduced motion); `types:` in the at-rule or `e.viewTransition.types.add()` in `pagereveal`. Detect `'onpagereveal' in window`. Support: Limited — Chrome/Edge 126+, Safari 18.2+, not Firefox; Navigation API Baseline Newly available (since 2026-01-13).
- MPA stability: `<script blocking="render">` for layout-critical scripts, `<link rel="expect" href="#hero" blocking="render">` until above-the-fold content parses (DOM only: preload and size hero images); ~4 s of blocking skips the transition; stale dynamic names block bfcache.

## Dialogs and popovers
- Invokers: `<button commandfor="id" command="show-modal|close|toggle-popover|show-popover|hide-popover">` (focus and `aria-expanded` native). Custom `command="--x"`: non-bubbling `command` event on the target (`event.command`, `event.source`), no semantics, set ARIA yourself. Detect `'commandForElement' in HTMLButtonElement.prototype`, then dynamic-import `invokers-polyfill`. Support: Baseline Newly available (since 2025-12-12).
- Popover: detect `'popover' in HTMLElement.prototype`, then `@oddbird/popover-polyfill`; select `[popover]:is(:popover-open, .\:popover-open)` or the rule is dropped. Support: Baseline Newly available (since 2025-01-27).
- Modal: always `showModal()` (top layer, focus trap, inert page, Esc/back-gesture dismiss = default `closedby="closerequest"`). `closedby="any"` adds backdrop light-dismiss; `none` = only `close()`. Act on `close`/`cancel`, not `click`. Support: Limited — Chrome/Edge 134+, Firefox 141+, not Safari; fallback: `click` with `target === dialog` outside `getBoundingClientRect()` → `close()`.
- Lock page scroll: `dialog:modal { overscroll-behavior: contain }` + `dialog::backdrop { overflow: hidden; overscroll-behavior: contain }` (backdrop defaults to `overflow: visible`). Never `overflow: hidden`/`position: fixed` on `html`/`body`. Not detectable. Support: Limited — Chrome/Edge 144+, Firefox 150+, not Safari.

## Interest invokers (tooltips, previews)
- Tooltip: `<div popover="hint" id="tip">` + `<button interestfor="tip">`. Browser adds role `tooltip`, `aria-describedby`/`aria-details`, Esc and light dismiss; don't add them. Tooltip stays hoverable and persistent (WCAG 1.4.13).
- Trigger is the implicit anchor: `[popover] { position-area: top; position-try-fallbacks: flip-block; margin: unset }` (anchor basics and support: see css.md).
- Previews: `interest`/`loseinterest` events on the target (`event.source`); `:interest-source`/`:interest-target`; `interest-delay-start/end`. No live-region announcements.
- Detect `HTMLButtonElement.prototype.hasOwnProperty('interestForElement')`, then the `interestfor` polyfill: `:is(:interest-source, .interest-source)`, delays via `--interest-delay-*` variables. Support: Interest invokers Limited — Chrome/Edge 142+, not Firefox/Safari; `popover="hint"` Limited — Chrome/Edge 151+, Firefox 153+, not Safari.

## Scroll-driven animation
- `animation: grow auto linear backwards, shrink auto linear forwards; animation-timeline: view(); animation-range: entry, exit;` with timeline/range after the shorthand (it resets them). `view(inline)` for horizontal scrollers; named `view-timeline: --tl` when another element animates; `timeline-scope` on a shared ancestor when it isn't a descendant.
- Gate: `@supports ((animation-timeline: view()) and (animation-range: entry))` (range test excludes partial support). No `scroll-timeline-polyfill`. Decorative = no fallback; else `IntersectionObserver` with 101 thresholds. Support: Limited — Chrome/Edge 115+, Safari 26+, not Firefox.
- After programmatic scroll: `await el.scrollIntoView({ behavior: 'smooth' })`, then `focus({ preventScroll: true })`. Superseded scrolls resolve, so guard with a counter. Unsupported returns `undefined` (await continues). Support: Limited — Chrome 150+, Edge 150+.
- Initial position: `scroll-initial-target: nearest` on one descendant (first in DOM wins; URL fragment and `scroll-start` beat it); instant, visual only. Fallback: `CSS.supports('scroll-initial-target','nearest')` else `scrollIntoView({ behavior: 'instant' })` on `DOMContentLoaded`. Support: Limited — Chrome/Edge 133+, not Firefox/Safari.

## Scroll snap state
- `scrollsnapchanging` (pending) / `scrollsnapchange` (settled) on the container; `event.snapTargetBlock`/`snapTargetInline`. Pending = class only; settled = `active` + `aria-current`. Nothing fires on load: compute the nearest item once. Support: Limited — Chrome/Edge 129+, not Firefox/Safari; fallback: `scroll` + `requestAnimationFrame` nearest-item, promote on `scrollend`.
- CSS-only highlight: item `scroll-snap-align: center; container-type: scroll-state`, then `@container scroll-state(snapped: x) { .card { … } }` (descendants only) under `prefers-reduced-motion: no-preference`. Not a focus signal. Support: Limited — Chrome/Edge 133+, not Firefox/Safari; fallback `IntersectionObserver` with `rootMargin: "0px -49%"`.

## Content reveal, highlight, DOM moves
- Find-in-page hidden content: prefer `<details>` (`name=` for exclusive groups); else `hidden="until-found"` + `beforematch` listener (bubbles) to sync `aria-expanded` and close siblings. Never set `display`/`visibility` on that element (style a child). Support: Limited — Chrome/Edge 102+, Firefox 148+, not Safari; fallback `!('onbeforematch' in HTMLElement.prototype)` → remove `hidden`.
- Highlight ranges without DOM edits: `TreeWalker(NodeFilter.SHOW_TEXT)` → `Range` on text nodes → `new Highlight(...ranges)` → `CSS.highlights.set('name', h)` (`clear()` first) → `::highlight(name)` (only color, background, decoration, shadow). Presentational; `<mark>` for meaning. Support: Baseline Newly available (since 2026-03-24); fallback `if (!CSS.highlights)` wrap in `<mark>`.
- Move without losing state (iframes, focus, animations, open dialogs/popovers): `parent.moveBefore(node, ref)`; custom elements get `connectedMoveCallback()` instead of dis/connectedCallback. Detect `'moveBefore' in Element.prototype`, else `insertBefore` (then `showModal()`/`showPopover()` again). Support: Limited — Chrome/Edge 133+, Firefox 144+, not Safari.
- Animated tab underline: anchor a `ul::before` indicator to `li.active` via `anchor-name`/`position-anchor` and `anchor()` insets, transition `inset` (`position-area` can't transition); keep `aria-current="page"`; fallback `border-bottom`. Anchor rules: see css.md.

## Gestures
- Drag: handle with `cursor: grab`, `touch-action: none`, `-webkit-user-select: none; user-select: none` (handle only). `pointerdown` stores the offset + `setPointerCapture`; `pointermove` while `hasPointerCapture`; clear on `lostpointercapture`. Clamp to the viewport; arrow keys move it too; `margin: 0` on dialogs before `left/top`. Support: `user-select` Limited — Chrome 54+, Edge 79+, Firefox 69+, not Safari.
- Swipe rows: a horizontal `scroll-snap-type: x mandatory` track, never a pointer-driven transform. Remove: `grid-template-columns: 100% 100% 100%; overflow: scroll clip; overscroll-behavior-x: none; scrollbar-width: none`, spacers and content `scroll-snap-align: start`, content `scroll-initial-target: nearest`; `IntersectionObserver` rooted at the track, thresholds `[0.2, 0.8]` (< 0.2 commits: collapse height, await `getAnimations({ subtree: true })`, remove); `MutationObserver` for added rows; offer undo. Reveal: `grid-template-columns: 100% max-content; overscroll-behavior: chain` (no local bounce; unsupported engines keep `auto`), panel `scroll-snap-align: end` with real `<button>`/`<a>`; `focusin` + `:focus-visible` on the content → `scrollIntoView({ inline: 'start' })` closes it.
