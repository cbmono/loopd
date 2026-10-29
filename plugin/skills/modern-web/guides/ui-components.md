<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/ui-components/ (14 guides) and guides/ui-atoms/ (12 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# UI components

Open for: cards, checkboxes, dark-mode toggles, dialogs, menus, dropdowns/tooltips/hovercards, toasts, drawers, progress/spinners, scrollspy, scroll-aware headers, carousels, responsive tables, icons.

## Shared support notes
- Popover: Baseline Newly available (since 2025-01-27). Polyfill `@oddbird/popover-polyfill` only if `!("popover" in HTMLElement.prototype)`; style `[popover]:is(:popover-open, .\:popover-open)`.
- Invokers (`command`/`commandfor`): Baseline Newly available (since 2025-12-12); `invokers-polyfill` only if `!('commandForElement' in HTMLButtonElement.prototype)`.
- Anchor positioning: Limited — Safari 27 (Sep 2026); unsupported in Chrome, Edge, Firefox. `@oddbird/css-anchor-positioning` needs explicit `anchor-name`/`position-anchor` and `anchor()` insets, not `position-area`; unpositioned popovers render centred.
- Scroll-driven animations: Limited — Chrome 115, Edge 115, Safari 26; unsupported in Firefox. Gate in `@supports (animation-timeline: scroll())` or the end keyframe applies statically; fallback a `scroll` listener, never scroll-timeline-polyfill.
- Scroll-state queries: Limited — Chrome 133, Edge 133; unsupported in Firefox, Safari. Fallback: IntersectionObserver on a zero-size sentinel.
- `@property`: Baseline Newly available (since 2024-07-09). Scroll snap / IntersectionObserver / `inert`: Baseline Widely available (since 2020-01-15 / 2019-03-25 / 2023-04-11).

## Card
- Root `<article>`; direct-child regions in source order: media first, heading, content (one `<p>`/`<ul>`/`<dl>` or one `<div>`), `<footer>` of native links/buttons. No wrapper divs, no CSS `order`.
- Whole card one destination, no other controls: `<a>` wraps the `<article>`. Click = action: `<button>`.
- Primary link + other controls: `.card-link` on the heading link only, stretched by `::after{position:absolute;inset:0}` over a `position:relative` card; lift `a:not(.card-link), button, input` with `position:relative;z-index:1`, never containers; ring via `.card:has(a.card-link:focus-visible)`.
- Choice: `<label class="card">` + direct-child radio/checkbox; `:has(> :checked)` changes colour/outline/shadow only, never border-width/padding/weight. Card options in a picker: `<select>` + `appearance: base-select` (see forms.md).
- `aspect-ratio` + `object-fit: cover` on the `<img>` itself. Size from the card (`container-type: inline-size`); side column only via `.card:has(> img)`; aligned rows via `subgrid`.

## Checkbox
- Pair with `<label>`; hit target ≥44px via the label, box in `em`; `:focus-visible`, never `outline:none`; style `:disabled`.
- `accent-color`: Limited — Chrome 93, Edge 93, Firefox 92, Safari 26.2 (Dec 2025); others ignore it. Safari may keep a white/black tick — test contrast.
- Custom: `appearance:none` on the input, explicit size, mark in `::before{background:currentColor;mask:var(--icon) center/contain no-repeat;scale:0}`, `scale:1` under `:is(:checked, :indeterminate)`; `forced-colors: active` ⇒ `CanvasText`. Masks: Baseline Widely available (since 2023-12-07).
- `indeterminate` is DOM-only (`el.indeterminate = true`); style `:indeterminate` distinctly.

## Dark-mode toggle & scoped schemes
- Default to the system; a persistent toggle is rarely needed. States: none / `"light"` / `"dark"` in `localStorage`, mirrored to `<meta name="color-scheme" content="light dark">`.
- The meta is only a hint; author `color-scheme` wins. Keep `:root{color-scheme:light dark}` plus `:root:has(> head > meta[name="color-scheme"][content="dark"]){color-scheme:dark}` (and `light`). No JS ⇒ system.
- FOUC: tiny inline script (not `module`/`defer`) after the meta sets `meta.content = localStorage.getItem("color-scheme") ?? "light dark"`; sync tabs on `storage`. Never clear the stored value when the OS later matches it.
- Toggle target = opposite of what is *rendered*; store it if it differs from the system, else remove the key. Always allow a return to system.
- Non-colour branching: `(prefers-color-scheme: dark)` combined with the `:root:has(meta…)` selector, never a JS class alone; ship both `<source>`s.
- Scoped scheme (code, players, embeds): `color-scheme: dark` (`only dark` to force) only on elements with their own background. `light-dark()` resolves at computed-value time: re-declare inherited `<color>` props (`color`, `accent-color`, `fill`) on the overriding element; never register design tokens as `<color>`. Safari ignores `color-scheme` in iframes — pass the theme explicitly. Support: color-scheme Baseline Widely available (since 2022-02-03); light-dark() Baseline Newly available (since 2024-05-13), fallback `prefers-color-scheme` on root tokens.

## Dialog
- Blocking (default): `<dialog aria-labelledby>` opened by `<button command="show-modal" commandfor="id">` or `showModal()`; the browser gives inert page, focus containment, top layer, `::backdrop`, Esc, focus return. Never `role="dialog"`, `aria-modal`, a focus trap, `inert` toggling, an Esc handler, `show()` or the `open` attribute.
- `dialog:modal{overscroll-behavior:contain}` + `dialog::backdrop{overflow:hidden;overscroll-behavior:contain}`; never `overflow:hidden`/`position:fixed` on html/body. Support: Limited — Chrome 144, Edge 144, Firefox 150; unsupported in Safari; `@supports` can't detect it.
- Non-blocking: `<dialog popover="manual|auto">`, or `dialog.show()` without top layer; visible close button. Menus/tooltips/toasts: semantic element + `popover`, not `<dialog>`.
- `autofocus` the primary field, or the safe action of a destructive confirm. Close via `<form method="dialog">`/`command="close"`; `command="request-close"`/`requestClose()` fires `cancel` first.
- `closedby`: `closerequest` (default), `any`, `none`. Support: Limited — Chrome 134, Edge 134, Firefox 141; unsupported in Safari — degrades to Esc-only, so keep dirty-form guards in `cancel`; polyfill click-outside with pointerdown+pointerup both outside `getBoundingClientRect()` (not `event.target`).
- In `close` read `returnValue` then reset to `''`. A prevented `cancel` shows a message linked by `aria-describedby` from the focused button, space reserved (`visibility`). Scope `display` to `dialog[open]`.

## Menu
- Items: command `<button type="button">`, destination `<a href>`. Arrow/Home/End/Esc make a menu; a short Tab-through link list is navigation, no menu roles.
- `<div focusgroup="menu nomemory" aria-labelledby="trigger">` nested inside `<div popover="auto">` (not on it: Chromium drops keys); no `role="menu"`/`menuitem` — focusgroup infers them. No browser ships focusgroup: if `!('focusGroup' in HTMLElement.prototype)` add the roles and Up/Down/Home/End yourself.
- Trigger `<button aria-haspopup="menu" aria-expanded commandfor="m" command="toggle-popover">` with the popover right after it (else implicit `aria-details`); no `popovertarget`. Submenu: `popover="auto"` after its trigger inside the parent focusgroup; a submenu trigger never also runs a command. `role="menubar"` only on a continuous bar (one Tab stop, Left/Right, hover switches).
- Position from the implicit anchor (invoker or `showPopover({source})`, Baseline Newly available since 2026-01-13): `position-area:block-end span-inline-end;inset:auto`; submenus `inline-end span-block-end` with `position-try-fallbacks: flip-inline, flip-block, --below` (`@position-try` under the trigger, indented, `min-inline-size:0`). Gate in `@supports (position-area: block-end)`, else position from script; never a centred menu.
- Script: move focus in `toggle`, not `command` (fires before open); restore focus to the trigger before `hidePopover()`, `focus({focusVisible:false})` after pointer use; `stopPropagation()` on Esc/ArrowLeft in submenus; set `aria-expanded` only in `toggle`; close all on outside `focusin`. Safe triangle: submenu `overflow:visible` + `::before` with `clip-path: shape()` to the near-edge corners, `(hover: hover)` only.
- `<hr>` separators; `role="menuitemcheckbox"`/`menuitemradio` + `aria-checked` (the one explicit item role), check from `[aria-checked="true"]::before`; fixed leading icon slot, no subgrid rows; ≤150 ms open/close via `display`/`overlay` `allow-discrete` + `@starting-style`.

## Anchored overlays (dropdowns, tooltips, hovercards)
- `<button popovertarget="p">` + `<div id="p" popover="auto">` = implicit anchor. Panel: `position-area: block-end span-inline-end; inset: auto; position-try-fallbacks: flip-block, flip-inline, flip-block flip-inline`; logical keywords only, never mixed with physical. Reset `inset`/`margin` only inside `@supports (anchor-name: --x)`.
- A revealed button group is not a menu: no `role="menu"`/`menuitem`/`aria-haspopup` without the keyboard contract (§Menu).
- Arrow that follows a flip: `container-type: anchored` on the positioned element, arrow in a child's `::before`, restyled under `@container anchored(fallback: flip-block)` (descendants only). Support: Limited — Chrome 143, Edge 143; unsupported in Firefox, Safari; gate the arrow in `@supports (container-type: anchored)`.
- Hovercard: `<a href interestfor="card">` + `<div id="card" popover="hint">`; the browser adds the `tooltip` role and `aria-describedby`/`aria-details` — add neither. `interest-delay: .2s .1s`; `:root:has(:interest-source) [interestfor]{interest-delay-start:0s}`. Enter/exit: `@starting-style` + `transition: opacity, transform, display, overlay; transition-behavior: allow-discrete` under reduced-motion `no-preference`. Optional cross-document morph: `view-transition-name` only under `:popover-open`; destination `<link rel="expect" href="#main" blocking="render">`.
- Support: Interest invokers Limited — Chrome 142, Edge 142; unsupported in Firefox, Safari — polyfill `interestfor` if `!HTMLButtonElement.prototype.hasOwnProperty("interestForElement")`, then style `:is(:interest-source, .interest-source)` and mirror delays in `--interest-delay-*`. `popover="hint"` Limited — Chrome 151, Edge 151, Firefox 153; unsupported in Safari. Cross-document view transitions Limited — Chrome 126, Edge 126, Safari 18.2; unsupported in Firefox.

## Toasts & tours (manual popovers)
- Toast: `popover="manual"` (no light dismiss, many coexist); close `<button popovertarget="t" popovertargetaction="hide">`; `hidePopover()` on a timer; stack via `sibling-index()` margins (fallback `[popover] + [popover]{margin-top:1rem}`); exit via `transition-behavior: allow-discrete`. Top-layer items ignore parent z-index — position each.
- Tour step: `popover="manual" role="dialog" aria-labelledby`; `anchor-name` on the feature, `position-anchor`/`position-area` + `inset:auto` on the step; focus into it after `showPopover()`; explicit Next/Close. `@supports not (anchor-name: --x)`: pin `position:fixed` at the viewport bottom.

## Navigation drawer
- `<div popover="manual">` (never `auto`/`hint`) > scroller `display:grid;grid-template-columns:var(--w) 100%;overflow-x:scroll;scroll-snap-type:x mandatory;overscroll-behavior:none` > `<nav tabindex="-1">` sheet `scroll-snap-align:start;height:100svh` (not vh/dvh); `::after` spacer `scroll-snap-align:end;scroll-initial-target:nearest`. Swipe is native scroll; reset the UA popover box (`width/height:auto;background:transparent;border:0;overflow:visible`).
- Open: `showPopover()` then `scroller.scrollTo({left:0, behavior:'auto'})` (`scroll-behavior:smooth` under reduced-motion `no-preference`). Close: scroll to `offsetWidth`; never `hidePopover()` directly.
- State: `IntersectionObserver` on the sheet `{root: drawer, threshold:[1/innerWidth, 1]}`, read `entries.at(-1)`; ratio 1 ⇒ `main.inert=true`, `aria-expanded="true"`, `sheet.focus()`; below threshold ⇒ `hidePopover()`, uninert. Backdrop tap (`!sheet.contains(target)`) and document Esc close.
- Backdrop fade: `@property --bd{syntax:'<number>'}`, `scroll-timeline: --fade x` on the scroller, `timeline-scope: --fade` + `animation-timeline: --fade` on the drawer, `::backdrop{opacity:calc(var(--bd)/2)}`, all inside `@supports (animation-timeline: scroll())`; else write the var from `scroll`.
- `scroll-initial-target` Limited — Chrome 133, Edge 133; unsupported in Firefox, Safari: else jump-scroll closed after `showPopover()` and wait two rAFs. No popover: drop the attribute, `position:fixed` + sibling backdrop — don't branch.

## Progress bar, ring, spinner
- Native `<progress>` (implicit `progressbar`); `max` for other scales; no `value` ⇒ indeterminate; name via `<label for>`/`aria-label`. No fallback text inside; never `tabindex`/`focus()` — announce completion via `role="status"`.
- Light styling: `accent-color`, `inline-size`, `writing-mode: vertical-lr`, post-paint effects — `border-radius`/`background`/`border` silently disable native rendering. Full custom: `appearance:none;border:0 solid;overflow:clip`; track on `progress`, fill in `::-webkit-progress-value` and `::-moz-progress-bar` in separate rules (grouping invalidates; `:is()` can't help), each once.
- Indeterminate bar: keyframes set `inline-size` (not `scale`) and `translate` in `cqi` (`progress{container-type:inline-size}`), `margin-right:auto` in `from,to`; never margins (break RTL); reverse under `:dir(rtl)`; never `animation:none` (zero-width fill in Chromium) — slow it for reduced motion. `animation: var(--bar-animation, revert-rule)`; revert-rule Baseline Newly available (since 2026-09-14).
- Ring: hide native parts; `--value: attr(value type(<number>))`; `background: conic-gradient(var(--fill) calc(var(--value)*1%), var(--track) 0); border: var(--t) solid transparent; background-origin: border-box; background-clip: border-area`; `@property --value{syntax:'<number>'}` for `transition: --value .4s` (0s unless reduced-motion `no-preference`); `[value="100"]` done state.
- Spinner: same ring, no `value`; `rotate: 1turn` keyframes 1.5s linear infinite, plus an arc-dash animation on `@property` angles appended via a `syntax:"*"` property's `initial-value` (drops out without `@property`); reduced motion ⇒ 6s, never stopped.
- Support: `background-clip: border-area` Limited — Chrome 150, Edge 150, Safari 18.2; unsupported in Firefox — `@supports not (…){mask-image:radial-gradient(transparent calc(50% - var(--t)), black …);border:0}`. Typed `attr()` Limited — Chrome 133, Edge 133, Firefox 155; unsupported in Safari — `MutationObserver` on `value` writing `--value`.

## Scrollspy
- `<nav>` of `href="#id"` links with `scroll-target-group: auto`; style `nav a:target-current`; unique matching ids, tall sections. Mirror to AT on load and `scrollend`: `aria-current="true"` on `querySelector('nav a:target-current')`. Not colour alone.
- Support: Limited — Chrome 140, Edge 140; unsupported in Firefox, Safari. Fallback `IntersectionObserver` (`rootMargin: '-50% 0px -50% 0px'`) toggling `.\:target-current`; style `nav a:is(:target-current, .\:target-current)`.

## Scroll-aware chrome
- Back-to-top and scroll hints: `container-type: scroll-state` on the scroller; sticky child hidden by default; `@container scroll-state(scrollable: top){.back-to-top{visibility:visible}}`, `scrollable: bottom` for a bottom shadow; hints `pointer-events:none`; pad content so the button never covers the last items. Unsupported browsers keep them hidden — nest the hidden state in `@supports (container-type: scroll-state)` if they must show.
- Stuck sticky header: `container-type: scroll-state; container-name: hdr` on the `position: sticky` element itself (not the scroller), always named; `@container hdr scroll-state(stuck: top)` styles descendants only. Box-model changes when stuck oscillate — `overflow-anchor: none` on the sticky element's direct parent (not root/body); no help for bottom-stuck.
- Shrinking header: fixed header, `@keyframes shrink{to{height:50px}}`, `animation: shrink auto linear both; animation-timeline: scroll(block root); animation-range: 0px 150px` (range end = size delta; timeline/range after the shorthand); pad `body` by the initial height; never `static`/`relative` with % ranges. Detect `@supports ((animation-timeline: scroll()) and (animation-range: 0% 100%))`.
- Scroll progress: `<div aria-hidden="true">` fixed, `transform-origin: 0 50%`, `scaleX(0→1)` keyframes, `animation: grow auto linear; animation-timeline: scroll()` under reduced-motion `no-preference`; named `scroll-timeline: --tl block` on `:root`, `timeline-scope` when not an ancestor. Animate `transform`/`opacity` only.

## Carousel slide effects
- `.scroller{overflow-x:scroll}`; slides `animation: fx auto linear both; animation-timeline: view(inline)` with 0/50/100% keyframes (`scale` .5→1→.5); named `view-timeline: --item inline` when the slide's children animate, `timeline-scope` to hoist. Detect `@supports ((animation-timeline: view()) and (animation-range: entry))` — the range check filters partial support. Fallback: paused `el.animate()` per slide, `currentTime` from a `scroll` listener.

## Responsive table
- Real `<table>`/`<thead>`/`<th>` + `<caption>`; wrapper `<div tabindex="0" role="region" aria-labelledby="caption-id">` with `overflow:auto; container-type: inline-size`; `border-collapse: separate`.
- `thead{position:sticky;inset-block-start:0;z-index:1}`; `tbody th{position:sticky;inset-inline-start:0;background:…}`.
- Narrow: `@container (width < 600px)` sets table parts `display:block`, `thead{display:none}`, `tbody th` sticky per card, labels via `td:nth-child(n)::before{content:var(--label-n) ": "}` (alt after `/` only for non-text).

## Icons
- CSS picks the icon ⇒ CSS icon system (mask = mono, background = colour); reuse with designed hooks ⇒ `<svg><use>`; arbitrary inner styling ⇒ inline SVG; never `<img>` + filters to recolour.
- Tokens `--icon-trash: url("data:image/svg+xml,…")` or root-relative URLs; relative URLs resolve against the *using* stylesheet — if unavoidable, `@property` the token with syntax starting `<url>` and declare on `:root` (not `<image>`/`initial-value`: Chrome and Safari resolve those against the document).
- Engine: `@property --icon-start{syntax:"*";inherits:false}` (same `--icon-end`); `@container style(--icon-start){::before{--icon-start:inherit;content:"" / var(--icon-style-alt, "");width/height:var(--icon-style-size, 1em);background-color:var(--icon-style-color, currentColor);mask:var(--icon-start) no-repeat center / contain;vertical-align:calc(0.5cap - var(--icon-style-size, 1em)/2 + var(--icon-style-voffset, -0.02em));flex:none;pointer-events:none;forced-color-adjust:none}}`; spacing only on `:not(.icon, :empty)`. Assign per selector (`.button-delete{--icon-start:var(--icon-trash)}`, swap on `[aria-expanded="true"]`); `.icon:empty{--icon-start:var(--icon)}` for icon-only, named by `aria-label` or `--icon-style-alt`; standalone informative ⇒ `role="img"` + `aria-label`.
- `<use>`: `viewBox` on the `<symbol>`; only inherited/custom properties cross (`fill="var(--x, currentColor)"`); external sprites same-origin only; inlined sprites share the page id namespace; decorative SVG `aria-hidden="true"`. CSS `d` Limited — Chrome 52, Edge 79, Firefox 97; unsupported in Safari.
- Support: Container style queries Baseline Newly available (since 2026-05-19) — fallback class hooks with `content: image-set(linear-gradient(transparent 0 100%), var(--icon-start)) / …` (invalid when unset, so the pseudo vanishes). Without `@property`, reset `--icon-start: initial` on descendants inside the style query. Safari: `::before, ::after{animation: webkit-301609 0s}` (empty keyframes) inside a WebKit-only `@supports`; register `--icon-start` as inheriting there and reset descendants in a `@layer`.
