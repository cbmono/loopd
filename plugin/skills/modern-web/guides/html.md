<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/html/ (8 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# HTML and web components

Open for: HTML semantics, images, dialog/popover/details, focus, forms, media; custom elements, shadow DOM, styling/ARIA across the boundary, form-associated elements, SSR.

## Semantics
- `<!DOCTYPE html>`, `<html lang>`, viewport `width=device-width, initial-scale=1.0`; never disable zoom.
- One `<h1>` per page/view; heading levels never skip.
- Landmarks `<header>`/`<nav>`/`<main>`/`<aside>`/`<footer>`; `<search>` over `role="search"`.
- `<button>` for actions (`type="button"` in forms), `<a>` only for navigation; `<ul>`/`<ol>`/`<dl>` for lists; bare boolean attributes.
- No `<div>` + ARIA where a native element exists; never `role="presentation"`/`aria-hidden` on focusable elements or their ancestors.
- Links/buttons need names; decorative SVG `aria-hidden="true"`, decorative `<img alt="">`.
- `<blockquote cite>` only for quotations; `<figure>`/`<figcaption>` only for captioned units; code blocks `<pre><code>`.

## Images
- `width`/`height` on every `<img>`/`<video>`.
- LCP image: `fetchpriority="high"`, never `loading="lazy"`; CSS-background LCP: `<link rel="preload" as="image" fetchpriority="high">`.
- `loading="lazy"` off-screen; `fetchpriority="low"` for trackers; `high` is zero-sum.
- `srcset` + `sizes` for sizes; `<picture>` + `<source media type>` + fallback `<img>` for art direction/formats.

## Dialog, popover, details
- Modal: `<dialog>` + `showModal()` (focus trap, Esc, `::backdrop`), `closedby="any"` for light-dismiss; `show()` is non-modal.
- `<form method="dialog">` closes without JS; button `value` becomes `returnValue`, read on `close`.
- Non-modal menus/tooltips: `popover="auto"` + `<button popovertarget="id">`; never `showModal()` on a `popover` element (`<dialog popover="auto">` is fine).
- `<details>`: `<summary>` first, no links/buttons in it; same `name` = exclusive accordion; style `details[open]`, `details::details-content`.
- A navigational heading: `<h2><button type="button" aria-expanded aria-controls>`, not `<summary>`. No `title` tooltips.

## Focus
- `inert` on hidden regions (off-screen menu, page behind a custom modal); pair with `opacity: .5`.
- `tabindex` only `0` or `-1`; tab order = DOM order, not CSS `order`.

## Forms, media, inline
- `form="id"` attaches an input outside its `<form>`; `<input list>` + `<datalist>` for light suggestions (unstylable).
- Never `autocomplete="off"` on credential/address/payment/contact fields; tokens (`email`, `cc-number`, `current-password` vs `new-password`) with matching `type` + `inputmode`. More: forms.md.
- `<video controls width height poster>` + `<source>`s + `<track kind="captions">`; native `controls` over JS.
- Background video: `muted`, no `controls`, `aria-hidden="true"` (valid only because it is non-focusable).
- Dynamic values reach CSS via `style.setProperty('--x', v)`; `addEventListener`, never `onclick=`.

## When to build a custom element
- Only for encapsulated state, a scriptable API, or behavior a native element can't express — never for a look; wrap a real `<button>` rather than re-creating it.
- In a framework codebase use its components; a custom element only for what must escape it (cross-app primitive, plain-HTML output).
- Tag kebab-case, ≥1 hyphen; semantic elements inside shadow templates. No customized built-ins (`is=""`): Safari has permanently declined them.

## Custom elements
- `connectedCallback` runs on every insertion — idempotent setup; `disconnectedCallback` drops global listeners/timers/observers; `connectedMoveCallback` replaces both on `Node.moveBefore()`.
- Constructor: `super()` first, no child access. Init in `connectedCallback` from attributes/children already present (late-defined elements upgrade in place); `slotchange`/`attributeChangedCallback` may still fire after connect.
- `observedAttributes` and hooks are snapshotted at `define()`; later additions are ignored.
- Hide undefined elements but fail open (never `body`): `my-el:not(:defined) { opacity: 0; animation: reveal .2s 2s forwards }` + `@keyframes reveal { to { opacity: 1 } }`.
- Attributes are strings — coerce. Boolean = present/absent (`hasAttribute`/`toggleAttribute`), never `"false"`. Guard `attributeChangedCallback` with `oldVal !== newVal`.
- Runtime style-only state (`busy`): `attachInternals().states.add/delete/has()`, styled via `:state()`; read-only outside, not serialized — markup-set or persisted state is an attribute.
- Never shadow `style`, `class`, `id`, `slot`, `part`, `title`, `lang`, `dir`; `disabled` is built-in only on form controls.

## Shadow DOM, templates, slots
- `attachShadow({ mode: 'open', delegatesFocus: true })`: `open` almost always; `delegatesFocus` when wrapping focusable controls (also forwards `<label>` clicks on FACE).
- One `<template>` at module scope, `append(template.content.cloneNode(true))` per instance; no per-instance `innerHTML`.
- Whitespace fills the default slot; `::slotted(:first-child)` matches the first Light DOM child, not the slot's first node.
- `slotchange` on the `<slot>` (incl. initial assignment) = children arrived: `e.target.assignedElements()`.
- Styles: `<style>` in template (copied per instance), `<link>` (FOUC), or one shared `new CSSStyleSheet()` (`replaceSync(css)`) in `adoptedStyleSheets` — fastest, no `@import`.

## Styling across the boundary
- Only inherited properties (`color`, `font-family`, custom properties) cross in. Theme via custom properties; never seed the public one on `:host`, alias it: `:host { --_bg: var(--card-bg, white); }`.
- `:host`, `:host([disabled])` from inside; avoid `:host-context()`. `::slotted(p)` reaches top-level slotted nodes only.
- `part="submit"` → `my-card::part(submit)`; few high-level parts; `exportparts="submit: card-submit"` forwards nested ones. Properties for constrained values, parts for open-ended styling.
- Wrapped native control: `font: inherit; color: inherit` on it (UA font doesn't inherit); `:host` rules don't reach it.
- `:host(:state(busy)) button {}` inside; `my-el:state(busy) {}` from the page — read-only hook, prefer over `data-*`.
- `@layer` works inside a shadow root, scoped to it. Container queries need `:host { display: block; container-type: inline-size; }` — default `inline` can't be a container.
- Support: `::part` Baseline Widely available (since 2020-07), `@layer` (2022-03), size container queries (2023-02); `:host-context()` Limited — Chrome 54/Edge 79 only, no Firefox/Safari.

## ARIA in shadow trees
- Default role/state via `ElementInternals` (`#internals.role = 'switch'; #internals.ariaChecked = 'false'`), not host attributes.
- Host is the control: `if (!this.hasAttribute('tabindex')) this.tabIndex = 0` in `connectedCallback` (throws in the constructor); handle `click` and Space; none on static hosts.
- Host wraps a focusable control: `delegatesFocus: true`, never with a host role/state.
- `aria-labelledby`/`-describedby`/`-controls` ids never cross a shadow boundary (silently ignored). `ariaLabelledByElements` etc. take element refs and resolve outward only (shadow → Light DOM). Else same tree or `aria-label`.
- Support: ARIA reflection Baseline Widely available (since 2023-10), fallback `setAttribute('role', …)`; `ariaLabelledByElements` Newly available (since 2025-04; Chrome 135, Edge 135, Firefox 136, Safari 16.4), fallback `aria-label`. See accessibility.md.

## Form-associated custom elements
- No hidden `<input>`. `static formAssociated = true` (mandatory), `#internals = this.attachInternals()`, `delegatesFocus: true`.
- `setFormValue(v)` on each change (`FormData` for multi-value); `setValidity({ valueMissing: true }, msg, anchorEl)` / `setValidity({})` to clear — blocks submit, `:invalid` applies, anchor focused on report. `:user-invalid` isn't reliably wired for FACE.
- Implement `formResetCallback()`, `formDisabledCallback(disabled)`, `formStateRestoreCallback(state)`; on disable, disable inner controls, never the host (`<fieldset disabled>` re-enable gets stuck; host already matches `:disabled`).
- Dispatch native `input` (per change) and `change` (on commit), not custom events.
- Support: Baseline Widely available (since 2023-03); detect `'attachInternals' in HTMLElement.prototype && 'setFormValue' in ElementInternals.prototype`; fallback: hidden native `<input>` kept in sync.

## Declarative shadow DOM
- SSR: `<template shadowrootmode="open">` as the host's first child, styles inside it.
- Hydrate: `if (!this.shadowRoot)` before `attachShadow`; attach listeners once; never re-render the server tree.
- Support: Baseline Widely available (since 2024-02); detect `Object.hasOwn(HTMLTemplateElement.prototype, 'shadowRootMode')`, else attach the root imperatively.
