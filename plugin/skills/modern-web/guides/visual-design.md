<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/visual-design/ (22 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Visual design: colour, dark mode, typography, effects

Open for: colour and contrast, dark mode, browser-UI theming, scrollbars, typography and text layout, masks and shapes, HTML-in-Canvas.

## Colour and contrast
- Never convey state by colour alone: add an `aria-hidden` icon or text.
- Contrast: 4.5:1 text; 3:1 large text, icons, control boundaries and states.
- `@media (prefers-contrast: more)` only to reinforce deliberately low-contrast accents.
- Forced colours strip `background-image`, `box-shadow`, `border-image`: under `@media (forced-colors: active)` use system colours (`CanvasText`, `ButtonText`, `Highlight`, `GrayText`) and a real `border`/`outline`; `forced-color-adjust: none` only where colour is information (a swatch).
- Tints: use a token; else `color-mix(in oklab, oklch(from var(--primary) 0.9 c h), white 30%)` (a bare `l` shift has no gamut mapping yet, `color-mix()` alone washes out; `l` shift ≤ 30%).
- Gradients and `color-mix()`: write `in oklch` (keeps chroma, may leave gamut) or `in oklab` (in gamut, may desaturate); `in srgb` only with a reason.
- Some pre-2024 browsers reject a gradient naming a space: write `linear-gradient(to bottom var(--in-oklab), a, b)` with `--in-oklab` empty on `:root` and `in oklab` inside `@supports (linear-gradient(in oklab, white, black))`; the preamble must never be empty. `color-mix()` needs no guard.
- Text on a dynamic background: `color: contrast-color(var(--bg))`; foreground only, never `background-color`.
  Support: Baseline Newly available (since 2026-04-10). Fallback, best first: relative colour `oklch(from var(--bg) max(0, sign(0.623 - l)) 0 h)` under `@supports (color: oklch(from red l c h))` (Baseline Newly available since 2024-09-16); `-webkit-text-stroke` + `paint-order: stroke fill`; `text-shadow`.

## Dark mode and theming
- `<meta name="color-scheme" content="light dark">` in `<head>` and `color-scheme: light dark` on `:root`, not `body` (else the root scrollbar stays light).
  Support: Baseline Widely available (since 2022-02-03). Fallback: switch tokens under `@media (prefers-color-scheme: dark)` on `:root`, not per component.
- Tokens: `--brand: light-dark(var(--brand-light), var(--brand-dark))`, raw values in their own properties.
  Support: Baseline Newly available (since 2024-05-13). Fallback: set the token under `prefers-color-scheme`, override inside `@supports (color: light-dark(white, black))`.
- A subtree with its own `color-scheme` must re-declare inherited colour properties (`accent-color`), even to the same token.
- Both `light-dark()` arguments share a type (`linear-gradient(blue)` makes a colour an image). `light-dark(url(a), url(b))`: Baseline Newly available (since 2026-09-14). Fallback: `image-set()` with a `type()` per option from a custom property, the inactive one `type("image/do-not-use")` (never `type("")`), swapped under `prefers-color-scheme: dark`.
- JS reading `matchMedia("(prefers-color-scheme: dark)").matches` must handle its `change` event. Most sites need no toggle.
- Iframes: Safari resolves `prefers-color-scheme` to the OS, not the parent `color-scheme`; pass the theme explicitly (`?theme=dark`, `postMessage`).
- `accent-color: light-dark(…)` on `html` for checkboxes, radios, sliders. Support: Limited availability; Chrome 93, Edge 93, Firefox 92, Safari 26.2. Safari may keep a white/black indicator: test both schemes.
- Style native controls, do not rebuild them: `::selection`, `::placeholder`, `::file-selector-button`, `field-sizing: content`, `resize: vertical`; `<select>` via `appearance: base-select` + `::picker(select)`; checkbox/radio/slider via `appearance: none` + pseudo-elements. `<button>`, never `<input type=submit>`.
- Validity: `:user-invalid`/`:user-valid`, never `:invalid`/`:valid` (flags empty required fields on load); exclude `input[type=range]`.
- `user-select: none` only on chrome, never on content text.

## Scrollbars
- `scrollbar-color: <thumb> <track>` and `scrollbar-width: auto | thin | none` on the scroller, colours in custom properties; thumb ≥ 3:1 against track; `none` only when scrolling has another affordance.
  Support: `scrollbar-color` Baseline Newly available (since 2025-12-12); `scrollbar-width` Baseline Newly available (since 2024-12-11).
- Never transition `scrollbar-color` (WebKit flickers).
- macOS ignores both unless `scrollbar-width` is set; the track stays transparent unless `scrollbar-gutter: stable` (hover only), and may anyway, so the thumb must not depend on it.
- `@media (prefers-contrast: more)`: black thumb on white track.
- Legacy fallback inside `@supports not (scrollbar-color: auto)`: `::-webkit-scrollbar { width: 12px; height: 12px }` (a size is required or colours never show), `::-webkit-scrollbar-thumb`/`-track { background: var(--…) }`.

## Typography and text layout
- Unitless `line-height` (`1.5`); `rem` not `px` for `font-size`; `overflow-wrap: break-word`; `text-align: start`; `max-width: 80ch` on prose; 200% zoom must work. No `justify` (else `hyphens: auto`), cursive body fonts or all-caps emphasis (`<em>`/`<strong>`).
- Fluid size: `clamp(2rem, 1rem + 5vw, 4rem)`, never bare `vw`.
- `text-wrap: balance` on headings and `<th>` (Chromium ≤ 6 lines, Firefox ≤ 10), not on boxed elements (the box does not shrink), never on `*`. Support: Baseline Newly available (since 2024-05-13).
- `text-wrap: pretty` on `p`, `blockquote`, `li`; not globally. Support: Limited availability; Chrome 117, Edge 117, Safari 26; unsupported in Firefox. Both degrade to `wrap`.
- `text-box: trim-both cap alphabetic` on badges, buttons, labels, flex-centred text (`trim-start` for a flush top): not inherited, both edges required, not for body copy. Support: Limited availability; Chrome 133, Edge 133, Safari 18.2; unsupported in Firefox (ignored).
- Poster lockups: `text-fit: grow per-line-all 300%` on the heading, each forced line a `display: block; white-space: nowrap` span; definite inline size required; `em` spacing does not scale. Support: Limited availability; Chrome 150, Edge 150; unsupported in Firefox and Safari. Fallback: `font-size: min(var(--text-fit-scale, 1) * 1em, 300%)` per line, scale measured in JS.
- `font-size-adjust: from-font` on the container so fallback fonts match the web font's x-height (a number like `0.51` when the base font is not an ancestor). Support: Baseline Newly available (since 2024-07-25). Fallback: `@font-face` `size-adjust`/`ascent-override`/`descent-override`.
- Native `text-decoration`, never borders or gradients, for a line along text: `:where(.x) { text-decoration: underline solid currentColor max(1px, 0.08em); text-underline-offset: 0.2em }`, thicker on `:hover, :focus-visible`. Real `<a href>`, never `javascript:void(0)`.
- `text-decoration-skip-ink: all` for CJK, `none` for thick lines (`auto` is default: omit it). Support (`all`): Baseline Newly available (since 2026-05-07). `text-decoration-skip-spaces` only with `white-space: pre`. Hover reveal: transition `text-decoration-inset: 0 100%` to `0 0` under `prefers-reduced-motion: no-preference`.
- Outlines: `background-clip: border-area` for a gradient ring (Support: Limited; Chrome 150, Edge 150, Safari 18.2; unsupported in Firefox; fallback: masked `::before`, `mask-composite: exclude`); `corner-shape: bevel | scoop | notch | squircle` + `border-radius` (degrades to rounded); `border-shape: polygon(…)` (Support: Limited; Chrome 147, Edge 147; unsupported in Firefox and Safari; fallback: evenodd `clip-path` ring on a pseudo-element, which also clips focus rings).

## Shapes and effects
- Layer several shadows; `filter: drop-shadow()` for non-rectangular shapes; `mix-blend-mode`/`background-blend-mode` scoped with `isolation: isolate`.
- Hard-stop gradient patterns (repeat position as `0`): stripes `linear-gradient(to right, a 50%, b 0) 0 / 2em`; diagonal `repeating-linear-gradient(-45deg, a 0 1em, b 0 2em)`. A gradient chart needs a data table (see accessibility.md).
- `mask-image` for free-form or soft-edged shapes, `clip-path` for geometric ones; always pair `-webkit-mask-*` with the unprefixed property.
  Support: Baseline Widely available (since 2023-12-07). Unmasked = plain rectangle, so content must read without it; `@supports (not (mask-image: url(x))) and (not (-webkit-mask-image: url(x)))` for a `clip-path` or overlay fallback.
- Inline SVG `<mask>` = luminance (white reveals, black hides, grey fades); file or gradient = alpha; override with `mask-mode`/`mask-type`. `maskContentUnits="objectBoundingBox"` scales 0–1 coordinates with the element.
- Cutouts: mask images directly; for cards with text, mask an empty sibling `div` of the same background, never the text container. Notch: `mask-image: radial-gradient(circle at 50% 0%, transparent 20px, black 21px)`.
- Scroll fade: `mask-image: linear-gradient(to bottom, black 80%, transparent)` on the scroller (keeps selection and pointer events). Texture: `mask-image: url(grunge.png); mask-repeat: repeat; mask-size: 300px`.

## Canvas (HTML-in-Canvas)
- Not natively supported by any major browser yet (Chrome 157): test `'content' in HTMLCanvasElement.prototype`; else overlay the HTML with CSS, export via `html2canvas`/`snapdom`, or the `three-html-render` polyfill.
- `<canvas content="drawable">` + `drawable` on every drawn element; size the backing store with a `ResizeObserver` (`device-pixel-content-box`) created outside `onpaint`; no cross-origin content.
- Draw in `canvas.onpaint` after `requestPaint()`, only when `event.changedElements` is non-empty: 2D `ctx.drawElementImage(el, x, y)` (hit-testing synced), then `toBlob()`/`captureStream()` export it.
- WebGL/WebGPU: `texElementSubImage2D`/`drawElementImageToTexture` into a texture sized from `captureElementImage()`, then `canvas.updateElementGeometry(el, { canvasTransform })` so clicks and AT bounds hit the real element.
