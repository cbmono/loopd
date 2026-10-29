---
name: modern-web
description: Modern web-platform guidance for browser-facing code — HTML, CSS, forms, accessibility, web performance (LCP/INP/CLS), client-side security (sanitising, CSP, passkeys), privacy, UI components (dialog, popover, menu, drawer, toast, carousel), animation and view transitions, dark mode and typography, dates and time zones. Open it before writing or reviewing anything that runs in a browser — a page, a component, a stylesheet, a form, a client-side script, a UI interaction — and apply the one guide the work falls under. Not for server-only code, CI, infrastructure, build tooling or tests.
user-invocable: false
---

# Modern web guidance

A condensed derivative of Google Chrome's `modern-web-guidance` skill
(`GoogleChrome/modern-web-guidance`, Apache-2.0), one file per kept category, pinned to the
upstream commit `NOTICE.md` names. **Open the guide for the category the work falls under
before writing** — one is usually enough, two when a task crosses them (a form inside a
dialog → `forms.md` + `ui-components.md`). Each guide is terse on purpose: every bullet is a
rule, an API or a gotcha that changes the code you write.

| Category | Open it when the work touches… | Guide |
|---|---|---|
| Accessibility | semantics, ARIA, focus and keyboard, live regions, error announcement, OS text scaling, generated content | `guides/accessibility.md` |
| CSS | layout, container queries, `:has()`, `@supports`/`@media` combinations, intrinsic sizing, design tokens, overflow, transforms, fluid scaling | `guides/css.md` |
| Forms | inputs and labels, validation timing, `autocomplete` and autofill, OTP, select / switch / slider, Enter-to-submit, branding form controls | `guides/forms.md` |
| HTML and web components | document structure, semantic elements, custom elements, shadow DOM, styling and accessibility of components, form-associated elements | `guides/html.md` |
| JavaScript | dates, times, durations, time zones, calendars, `Temporal`, `Intl` | `guides/js.md` |
| Performance | LCP / INP / CLS, loading and fetch priority, long tasks and scheduling, `content-visibility`, lazy media, prerender / speculation rules, analytics beacons | `guides/performance.md` |
| Privacy | data minimisation, cookies and storage, third parties, headers, fingerprinting surface, permissions | `guides/privacy.md` |
| Security | untrusted HTML, Trusted Types and CSP, origins and `postMessage`, subresource integrity, outbound connections, passkeys / WebAuthn, sign-in flows | `guides/security.md` |
| UI components | dialog, popover, menu, navigation drawer, card, checkbox, toast, progress and spinner, tooltip and hovercard, dropdown, carousel, responsive table, icons, sticky or shrinking headers | `guides/ui-components.md` |
| UI behaviours | motion and reduced motion, view transitions, entry / exit animation, light dismiss, scroll-driven effects and scroll snap, invokers and interest, drag and swipe gestures | `guides/ui-behaviors.md` |
| Visual design | colour and contrast, dark mode and theming, scrollbars, typography and text layout, font fallbacks, shapes, masks and fades | `guides/visual-design.md` |

## Reading a guide

- **Baseline Widely available** features are safe without a fallback. For anything a guide
  marks **Newly available** or **Limited availability**, apply the fallback the guide gives —
  unless the project's own `CLAUDE.md` states a browser-support policy, which then wins.
- The guides are vanilla HTML / CSS / JS. **Adapt to the framework without dropping the
  feature**: spread a newly shipped attribute past the type checker
  (`{...({ popover: 'hint', commandfor: id } as any)}`), guard `window` / `HTMLElement`
  under SSR, load a polyfill with a bare dynamic `import('<pkg>')` in a client effect,
  call `showModal()` / `moveBefore()` through refs on nodes the framework does not own,
  generate per-instance ids and `anchor-name`s (`useId()`), and keep `:root` and
  `@starting-style` top-level and unscoped.
- A compatibility line appears only where upstream stated one; where a guide says nothing
  about support, it made no claim — do not invent one.
- **Say which guide you used.** An engineer names it on the PR's `Verified:` line; a
  reviewer names it in the review. Server-only work opens nothing here.
