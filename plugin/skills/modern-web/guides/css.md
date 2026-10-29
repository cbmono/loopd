<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/css/ (18 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# CSS

Open for: cascade and selectors, design tokens, layout (flex, grid, container queries, overlays, overflow), `:has()`, style queries, intrinsic-size animation, `@function`, feature detection.

## Foundations
- Built-ins before variables: `currentColor`, `inherit`, `em`, `cqi`/`cqb` over repeated values. Duplicate code is fine; duplicate knowledge is not.
- Logical properties (`margin-inline-start`, `inline-size`) unless "flip in RTL?" is no.
- `corner-shape: squircle` as enhancement; elliptical `border-radius: 10px / 20px`.
- Focus, touch targets, generated content: accessibility.md. Colour, dark mode, type, effects, motion: visual-design.md. `content-visibility`: performance.md.

## Cascade
- No BEM. `@layer reset, base, theme, components, utilities;` declared up front; every rule in a layer; incidental filters wrapped in `:where()`.
- `inherit`/`initial`/`unset`/`revert` over restated values (`transition: inherit`). No `*` resets — web components and lower layers cannot override them without `!important`.

## Selectors & scoping
- `:has()` over JS-managed classes (`label:has(:checked)`); never nest `:has()` or put pseudo-elements in it.
- `details:nth-child(1 of [open])` is the first open details; `details[open]:first-child` only matches an open first child.
- Pseudo-class fallbacks via forgiving `:is()`/`:where()` (`[popover]:where(:popover-open, .\:popover-open)`), never duplicated rules; pseudo-elements are invalid inside.
- `:not()` over overrides that reordering breaks (`li:not(:last-child)`, `button:hover:not(:disabled)`); overrides are fine for specialisation (`button.primary`); `revert-layer` for an unavoidable one.
- `@scope (.card) to (.content)` excludes a subtree (`.card :not(.content *)` fails when nested); `@scope (.dark) { .invert { … } }` lets the nearest ancestor win where `.dark .invert`/`.light .invert` tie.
- `sibling-index()`/`sibling-count()` (Baseline Newly available since 2026-08-18) for per-sibling maths in `calc()`; fallback: JS sets 1-based `--sibling-index`/`--sibling-count` inline behind `!CSS.supports('top: calc(sibling-index() * 1px)')`, native functions only inside `@supports`.

## Design tokens
- Custom properties on `:root`; no nontrivial inline values (`padding: 0` fine; `.3em`, `#f06` not) outside test cases.
- Tiers: literal (`--color-blue-10`) → semantic (`--color-accent`) → UI (`--ui-border`) → component (`--button-bg-primary-hover`); follow existing conventions.

## Layout
One row/column → flexbox; align to grandparent tracks → subgrid; rows and columns → grid; balanced prose → multi-column; packed varied heights → grid + `grid-auto-flow: dense`; tethered overlay → anchor positioning.
- `min-content`/`max-content`/`fit-content()`, `fr`, `minmax()`, `aspect-ratio` before fixed sizes or media queries; `place-*` aligns both axes.
- Never `overflow: hidden` to mask a bug; the gap under inline replaced elements (`<img>`, `<svg>`, `<video>`) is fixed by `display: block`.
- Support: `sv*`/`lv*`/`dv*` viewport units Baseline Widely available (since 2022-12-05). `dvh`/`dvw` on mobile; never `100vw` (ignores the scrollbar) — `100%`, `100dvw`, `100svw`.
- Masonry: Grid lanes not natively supported by any major browser; `grid-template-rows: masonry` only inside `@supports`, else `grid-auto-flow: dense` or `columns` + `break-inside: avoid`.

## Flexbox
Support: `flex-wrap: balance` Limited — Chrome 150, Edge 150 only (falls back to `wrap`).
- `flex-wrap: wrap` whenever overflow is possible, `flex-wrap: balance` after it on pill/tag rows; `flex: <grow> <shrink> <basis>`; `gap`, not margins; `align-items: safe center`; `margin-inline-start: auto` pushes one item to the end; `min-inline-size: 0` on items with unbreakable content.
- Don't: `justify-self` (auto margins instead); `order`/`*-reverse` on interactive content (tab order stays DOM order); `space-around` for `space-evenly`; forget `column` moves `justify-content` to the block axis; `width` beside `flex-basis` (basis wins).

## Grid & subgrid
Support: Subgrid Baseline Widely available (since 2023-09-15).
- Known columns → explicit tracks or `grid-template-areas`; unknown → `repeat(auto-fit, minmax(240px, 1fr))` (`auto-fit` stretches the last row, `auto-fill` keeps ghost tracks) — size comes from `repeat()`, never content; needs a definite container `inline-size`.
- Subgrid on the axis children must inherit; variable child count → one axis only, `grid-auto-rows` for the other; `grid-template-rows: auto 1fr;` before `grid-template-rows: subgrid;` as fallback.
- Don't: `grid-auto-flow: dense` on interactive content; confuse `*-items` (within track) with `*-content` (tracks within container).

## Container queries
Support: Container queries (size) Baseline Widely available (since 2023-02-14); fallback: `@media` + `@supports (container-type: inline-size)`.
- Component context → container query; page layout and `prefers-*` → media query.
- `container-type: inline-size` on a wrapper, or `size` with a definite `block-size` (containment ignores content; `block-size` is not a type); nested contexts: `container: card / inline-size` → `@container card (inline-size > 400px)`.
- `cqi`/`cqb`, `cqw`/`cqh`, `cqmin`/`cqmax` work on any property without `@container`; no qualifying ancestor → `svw`/`svh`.
- Fluid type `clamp(1rem, 5cqi, 2.5rem)`, max ≤ 2.5× min; viewport version `clamp(2rem, 1rem + 5vw, 4rem)`, never bare `vw`.

## Overlays
Support: `<dialog>` Baseline Widely available (since 2022-03-14); Popover Newly available (since 2025-01-27); Anchor positioning Limited — Safari 27 only.
- `popover` for transient non-modal UI (top layer, no `z-index`); `<dialog>.showModal()` for modal focus-trapped UI; never both on one element.
- `anchor-name` on trigger, `position-anchor` on overlay; `position-area` (or `anchor()` in insets), `anchor-size()`, `position-try-fallbacks: flip-block`/`flip-inline`; one coordinate system per `position-area`; gate with `@supports (anchor-name: --x)` + absolute fallback. See ui-components.md.

## Overflow & clipping
Support: `overflow: clip` Baseline Widely available (since 2022-09-12); `overflow-clip-margin` Limited — Firefox 148 only; `scrollbar-gutter` Newly available (since 2024-12-11); `line-clamp` not natively supported by any major browser.
- `overflow: auto`, not `scroll`. `clip` clips without a scroll container (`hidden` makes one scripts can scroll) but disables all scrolling — not on scripted scrollers or `position: sticky` containing blocks.
- `overflow-clip-margin` needs `overflow: clip`: `content-box` (concentric corners), `padding-box`, `border-box`, or a length (`content-box 15px`) so child shadows bleed; gate with `@supports (overflow-clip-margin: 15px)` over `overflow: hidden`.
- `scrollbar-gutter: stable`; `overscroll-behavior: contain` on nested scrollers, `chain` on wrappers passing scroll up.
- Truncation: `display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; line-clamp: 3;` (the prefixed triad is specified, not deprecated).

## Parent styling with :has()
Support: `:has()` Baseline Widely available (since 2023-12-19); `:user-valid`/`:user-invalid` Baseline Widely available (since 2023-11-02).
- Container from child state (`.card:has(:checked)`, `.field:has(:user-invalid)`) or content (`.card:has(img)`, `:not(:has(img))`); switch custom properties on the container; scope to the nearest container, not `body`.
- Critical use needs a fallback: `@supports not selector(:has(*))` + a class toggled by JS behind `!CSS.supports('selector(:has(*))')`; for content presence let the template add `.has-image`.
- `:user-invalid` sets no ARIA — sync `aria-invalid` on `blur` (capture) and `input` via `el.matches(':user-invalid')`.

## Style queries
Support: Container style queries Baseline Newly available (since 2026-05-19); not for core features yet.
- `@container style(--prop: value)` matches descendants of the element setting `--prop`, never that element; no `container-type` needed.
- Tokens: `.features { --density: compact }` → `@container style(--density: compact) { .card { padding: 8px } }`; variants: a semantic flag (`--surface: featured`) components opt into, neither side naming the other; descendant selectors for fixed one-off relationships.
- Combine selector + media criteria once on an ancestor's custom property (`:root { @media (prefers-color-scheme: dark) { --color-scheme: dark } }`) and branch on `style(--color-scheme: dark)`; visibility utilities: `not style(…)` + `display: none !important`.
- Fallback: `:where()` selector version first, style query after at equal specificity (source order wins; selector fallbacks cannot nest contexts).

## Animating to intrinsic sizes
Support: `interpolate-size` and `calc-size()` Limited — Chrome 129, Edge 129 only (others jump).
- `interpolate-size: allow-keywords` on `:root`, then transition `block-size: 0` ↔ `auto`/`min-content`/`max-content`/`fit-content`; one end must be a length/percentage.
- `calc-size(<basis>, <calc-sum>)` only when the value needs maths (`calc-size(max-content, size + 20px)`); `size` only in the second argument; one intrinsic keyword per call; percentages resolve against the container. Plain keyword first: `block-size: auto; block-size: calc-size(auto, size + 2rem);`.
- Respect `prefers-reduced-motion`; `hidden` on `transitionend` when collapsed to zero; sync `aria-expanded`; never measure in JS.

## Individual transforms
Support: Individual transform properties Baseline Widely available (since 2022-08-05).
- `translate`, `rotate`, `scale` over re-declaring a `transform` chain per state; fixed order translate → rotate → scale → `transform`; they compose (`scale: 2; transform: scale(3)` = 6×).
- Identity values on the base state (`translate: 0px; rotate: 0deg; scale: 1`) so a hover transform does not create a stacking context mid-interaction.

## @function and at-rule detection
Support: `@function` Limited — Chrome 139, Edge 139 only; `@supports at-rule()` Limited — Chrome 148, Edge 148, Firefox 157 only (use only for at-rules newer than itself).
- `@function --cols(--n <number>) { result: 1fr; @media (min-width: 800px) { result: repeat(var(--n), 1fr); } }`, used as `grid-template-columns: 1fr; grid-template-columns: --cols(2);` — plain value first.
- Dashed names and params; defaults with `:`; types `<color>`, `type(<number> | <percentage>)`, `returns <type>`; the last matching `result` wins (cascade, not early return) — default first.
- Never wrap an at-rule in a check for itself (unknown rules are already ignored); `at-rule()` matches names only — probe `@supports (color: --foo())` for `@function`, `@container style(--a: 1) or (not (style(--a: 1)))` for style queries; JS detection sets a root class, CSS branches.
