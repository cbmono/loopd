<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/accessibility/ (4 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Accessibility
Open for: HTML/ARIA, forms, focus, dialogs, media, live regions, CSS `content`, text scaling.

## Structure
- Landmarks hold all content: `<header>`, `<nav>`, one `<main>`, `<aside>`, `<footer>`; several `<nav>`s get distinct `aria-label`s (no role name); don't label `<section>` unless nothing else fits.
- Real `<h1>`–`<h6>`, one `<h1>` per page (a modal may add one), no skipped levels; no heading inside `<summary>` (child roles get stripped) — wrap a button in a heading.
- `<ul>`/`<ol>` for repeated items only; never for paragraphs or checkbox/radio groups.
- Tables: `<caption>` + `<th scope="col|row">`; never for layout.
- Skip link before repeated blocks (max two), targeting the first meaningful element via `tabindex="-1"` (`<h1 id="content" tabindex="-1">`).

## Semantic HTML and ARIA
- Native first: `<button>` not `<div role="button">`, `required` not `aria-required`; ARIA only for widgets HTML lacks (tabs, tree).
- No redundant roles (`<ul role="list">`), except Safari drops list semantics from `<ul>`/`<ol>` outside `<nav>` with `list-style: none` or `display: flex|grid` — add `role="list"` there.
- Interactive roles on a child, not the structural element: `<li><span role="button">`; same-kind overrides (`<ul role="tree"><li role="treeitem">`) are fine.
- `role="tab"` must behave like a tab, keyboard included; toggles expose `aria-expanded`/`aria-pressed`.
- `disabled` removes focus (even with `tabindex="0"`); `aria-disabled="true"` keeps it but you must block activation in JS — prefer it for toolbars and links.
- Never `aria-hidden="true"` on focusable elements or their ancestors; never `role="presentation|none"` on interactive elements.

## Names and descriptions
- Native naming: `<label for>`, `<caption>`, `<legend>`, `<figcaption>`; always explicit `for`/`id`, even when nesting (voice control needs it).
- Visible label → `aria-labelledby`, not `aria-label`. Never name via `title` (hover-only; `<iframe>` excepted) or `placeholder`; `aria-label(ledby)` only on widget, landmark, image or iframe roles, not bare `<div>`/`<span>`.
- Visible text appears verbatim in the name. Same target → same name; different action → different name (`Edit <span class="visually-hidden">name</span>` or `aria-label="Edit name"`).
- Instructions, errors, hints: `aria-describedby` (visible) or `aria-description` (screen-reader only), never in the label; don't restate `required` or ARIA state; the target must read alone (id plain text, not a trailing link).
- `aria-invalid="true"` announces only "invalid": pair with the message as description, set only while it shows.
- Visually hidden utility: `.visually-hidden:where(:not(:focus-within, :active))` → `position: absolute; clip-path: inset(50%); overflow: hidden; width: 1px; height: 1px; margin: -1px; padding: 0; border: 0; white-space: nowrap`, all `!important`.

## Language, titles, iframes
- `<html lang="en">`; mark inline changes (`<span lang="de">`); never a mismatching `lang`.
- Unique, non-empty `<title>` per page (iframed too), unique part first (`Topic | Site`); SPAs update it on route change.
- `<iframe title="…">` always; never `scrolling="no"` or `overflow: hidden` on iframes.

## Keyboard and focus
- Tab order = reading order; never positive `tabindex`; `tabindex="0"` only on role-bearing elements that are not natively focusable, never on static or hidden content.
- Custom button-likes: Enter on `keydown`, Space on `keyup` (`preventDefault` the keydown). Native controls need no handlers; `<a role="button">` still needs Space `keyup`.
- Style `:focus-visible`, not `:focus`; prefer the browser ring. `outline: none` only with a ≥ 3:1 `outline` + `outline-offset` replacement; `box-shadow` rings need an `outline` fallback under `@media (forced-colors: active)`.
- Targets ≥ 24×24 CSS px via `min-inline-size`/`min-block-size` or padding, not `width`/`height`; enlarge under `@media (pointer: coarse)`.
- `touch-action: pan-y`/`pan-x` for custom gestures, never `none` (except a drawing canvas).

## Images, SVG, media
- Every `<img>` has `alt`: purpose, not appearance ("Search", not "Magnifying glass"); `alt=""` when decorative; no "Image of…"; charts: long description via `<figcaption>`/`aria-describedby` plus a data table.
- Inline SVG: informative → `role="img"` + child `<title>` or `aria-label`; decorative → `aria-hidden="true"`.
- Media: verbatim transcript (link via `aria-details`), WebVTT captions incl. non-speech cues (`<track kind="captions">`), audio description.
- Visibility: screen-reader-only → `.visually-hidden`; visual-only → `aria-hidden="true"`; hidden for all → `hidden`; never `aria-hidden` on anything focusable.

## Generated content
- Never carry meaningful text (labels, state, instructions) in CSS `content`; keep it in the DOM.
- Alt argument `content: url(cloud.svg) / "Save";` only when the text differs from the value and isn't in the DOM already (`<button>Save</button>` + alt "Save" → "Save save").
- Silence decorative text: `content: "→" / "";` — not for images, already presentational.
- Emoji: alt text only when the meaning differs from its name (`"🎉" / "Yay!"`, not `"celebration"`).

## Forms
- Every control has `<label for>`; placeholders are hints only. Hint text above the input, linked via `aria-describedby` (autocomplete popovers cover text below).
- `autocomplete` with the right token (`email`, `given-name`) on fields collecting personal data.
- `required` (`aria-required` only when `required` can't apply). Never submit or navigate on focus/change alone.

## Error announcement
- Style `:user-invalid`, not `:invalid` (flags untouched required fields). Link the message via `aria-errormessage` (or `aria-describedby`, wider support); show it with `input:user-invalid ~ .error-msg`.
- `aria-invalid` doesn't track `:user-invalid`; sync it in capture-phase `focus`/`blur` listeners (they don't bubble) and on `input` while invalid: `el.matches(':user-invalid') ? el.setAttribute('aria-invalid', 'true') : el.removeAttribute('aria-invalid')`.
- Support: Baseline Widely available (since 2023-11-02); Chrome 119, Edge 119, Firefox 88, Safari 16.5. Fallback if `!CSS.supports('selector(:user-invalid)')`: track interacted+blurred per field in a `WeakMap`, toggle `.user-invalid-fallback` (styled like the pseudo-class) and `aria-invalid` via `checkValidity()`; clear on form `reset`.
- `aria-errormessage` is read on focus, not on appearance; for immediate announcement add `role="alert"`/`aria-live="polite"`; test for double announcement.

## Live regions
- `assertive`/`role="alert"` only for critical, blocking updates (session timeout); `polite` for status ("Saved"); `off` for passive text.
- Dynamic errors: live region or move focus to the error list. No "Loading…" announcements — use `<progress>`/`role="progressbar"`.
- One `polite` and one `assertive` region per page (or the framework's); debounce rapid updates; delay slightly while the user types or focus moves.
- Don't update live regions inside `inert` DOM or behind a modal — they go unannounced.

## Dialogs and overlays
- `<dialog>` + `.showModal()`: outside content goes inert, no focus trap needed. Name with `aria-labelledby`, close with `.close()`, return focus to the trigger.
- Custom overlay only when `<dialog>` can't work: `role="dialog"`, `inert` on everything outside (overlay not a descendant), move focus in.

## OS text scale
- Opt in with `<meta name="text-scale" content="scale">` in `<head>`; the browser scales `1rem` to the OS setting.
- Support: Limited availability — Chrome 146 (Mar 2026), Edge 146 (Mar 2026); unsupported in Firefox and Safari (default size, manual zoom).
- Never set `font-size` on `:root`/`html`; never combine the meta with `env(preferred-text-scale)` — double scaling. A base size goes on `body`, only if needed.
- `rem`/`em` sizes, unitless `line-height`, text-coupled spacing in relative units; fluid type keeps a font-relative part (`clamp(2rem, 1.25rem + 2vw, 4rem)`, never `5vw` alone), max ≤ 2.5× min.
- Breakpoints in `em` or container queries, not px. Text containers grow: no fixed `height`/`max-height`, no `white-space: nowrap` on sentences; grids `repeat(auto-fit, minmax(min(100%, 16rem), 1fr))`.
- Test at 200% text size and a 320 px viewport: no clipping, overlap or two-dimensional scrolling.

## Testing
- axe-core/Lighthouse (a 100 score proves nothing), then a keyboard-only pass (everything reachable, focus never sticks) and screen readers: JAWS+Chrome, NVDA+Firefox, VoiceOver+Safari, TalkBack+Chrome.
- Contrast, forced-colors, typography, motion: see css.md.
