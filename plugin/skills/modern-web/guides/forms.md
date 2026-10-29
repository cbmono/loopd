<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/forms/ (19 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Forms

Open for: forms, inputs, selects, switches, sliders; sign-in/up, address, payment, OTP; validation UX; styling native controls.

## Structure
- `<form action method>`: `POST` for sensitive data and mutations, `GET` only for idempotent requests (search).
- Every control has a `name`; real `<button type="submit">`, `<textarea>`, `<select>` — never `div`/`span` controls or `type="button"` on the primary submit.
- `<fieldset>`/`<legend>` for groups; submit labels name the action ("Sign in", "Proceed to payment"), not "Continue".
- Selection: 1–5 exclusive → radios; 6+ → `<select>`; 10+/dynamic → `<input list>` + `<datalist>`; multi → checkboxes.

## Labels and state
- `<label for>` ↔ `id` on every control; label above; label-to-input gap smaller than group gap; `lang` on `<html>`.
- `placeholder` is never the label nor the only format hint. Hints and rules sit *above* the input, linked by `aria-describedby` — below, the keyboard or autofill popover hides them.
- Mark required fields before interaction (asterisk); `aria-live` for dynamic errors; a non-color cue for every state; never drop the focus outline without `:focus-visible { outline: 3px solid …; outline-offset: 2px }`.

## Autofill and input hints
- `autocomplete` on every control; autofill also needs a stable `name`/`id` inside a `<form>` with a submit button.
- `type="email"` / `type="tel"` always; `inputmode="numeric"` for PINs, codes, card and postal numbers — never `type="number"` for identifiers (drops leading zeros, scroll edits the value).
- `enterkeyhint`: `next`/`previous` across multi-page steps, `done` on the last input, `search` on search.
- Identifier fields: `autocorrect="off" autocapitalize="off" spellcheck="false"`; `type="email"` already covers the first two.
- One input per name, card number, phone, PIN — never split; accept spaces in card numbers. Names: Unicode `pattern="[\p{L}\.\- ]+"`, never Latin-only. `required` on mandatory fields.

| Form | Tokens |
|---|---|
| Sign-in | `username` on the email input (keep `type="email"`), `current-password` |
| Sign-up | `name`, `username` on email, `new-password` (never `current-password`), `tel` |
| Address | `street-address` on a `<textarea>` — or `address-line1`/`-line2`/`-line3`, only line 1 required; `address-level2` (city); `postal-code` (`type="text"`, optional) |
| Payment | `cc-number` (`inputmode="numeric" pattern="[\d ]{13,19}"`), `cc-name`, `cc-exp` (MM/YY), `cc-csc` (`type="text" inputmode="numeric"`, never `password`); prefix `shipping `/`billing ` when both exist |

- Sign-in/up: never ask twice; allow paste; "Show password" toggle (`aria-pressed`) and "Forgot password" link; email, password and submit above the fold.
- Support: `email`/`tel` types, `autocomplete`, `inputmode`, `enterkeyhint` Baseline Widely available; `autocorrect` Newly available (since 2026-09-11). Autofill is progressive enhancement — no fallback code.

## SMS OTP
- One `<input type="text" inputmode="numeric" autocomplete="one-time-code" pattern="\d{6}" maxlength="6" required>` in `<form method="POST">` with a submit button, hint above. Never `type="number"`, `type="tel"` or six `maxlength="1"` boxes (style one input with `letter-spacing` instead).
- SMS: readable sentence first; **last line** exactly `@example.com #123456` — `@` first, host only, one space, nothing after.
- WebOTP (secure context): if `'OTPCredential' in window`, `navigator.credentials.get({ otp: { transport: ['sms'] }, signal })` on OTP-step mount and resend; `abort()` on manual submit, resend and unmount; on resolve `input.value = otp.code; form.requestSubmit()` — never `form.submit()`; swallow `AbortError`.
- Cross-origin iframe (3-D Secure): last line `@shop.example #123456 @bank.example`, parent header `Permissions-Policy: otp-credentials=(self "https://bank.example")`, `<iframe allow="otp-credentials">`.
- Support: WebOTP Limited — Chrome 93, Edge 93, Safari 27; unsupported Firefox. Permissions Policy Limited — Chrome 108, Edge 108; unsupported Firefox and Safari. No polyfill — degrade to keyboard suggestion, then manual entry; prefer passkeys.

## Validation
- Native constraints first: `required`, `minlength`, `maxlength`, `pattern`, `type`. `pattern` is a full match (implied `^…$`); password rules via lookaheads `(?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[\W_]).{8,}`.
- Style `:user-invalid` / `:user-valid`, never bare `:invalid` (matches on load). They match after blur-with-change or a submit attempt (which focuses the first invalid) and clear the instant the value is fixed. `input` only clears errors; `blur` checks; `submit` blocks. Server-side validation is mandatory.
- Keep submit enabled; disable only *after* a valid submission. Custom text: `setCustomValidity('…')` in `invalid`, `setCustomValidity('')` on `input`.
- Error markup: `aria-errormessage="id"`; `.error-msg { display: none }` shown by `input:user-invalid + .error-msg`. Never hide a rules list until the field is valid.
- `:user-invalid` sets no ARIA — on `blur` (capture) and `input`: `el.setAttribute('aria-invalid', el.matches(':user-invalid'))`; on `submit` sync every `[required]`.
- Required `<select>`: first option `<option value="" disabled selected>`.
- Support: `:user-valid`/`:user-invalid` Baseline Widely available (since 2023-11-02). Fallback when `!CSS.supports('selector(:user-invalid)')`: a `WeakMap`-tracked `.user-invalid-fallback` class + `aria-invalid` from `checkValidity()`.

## IME-safe Enter submit
- Any custom Enter `keydown` handler (textarea or input) bails while `event.isComposing`. Native implicit submission and `Cmd/Ctrl+Enter` need nothing.
```js
el.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.shiftKey) return;   // no shiftKey test on <input>
  e.preventDefault();                              // no newline, no double submit
  if (e.isComposing || e.keyCode === 229) return;  // 229: Safari's out-of-order keydown
  form.requestSubmit();
});
```
- If `keyCode` is banned: store `event.timeStamp` on `compositionend`, bail when `Math.abs(keydown.timeStamp - last) < 50` (never `Date.now()`). Keep a real submit button.
- Support: `KeyboardEvent.isComposing` Limited — Chrome 56, Edge 79, Firefox 31; unsupported Safari (hence the 229 check).

## Layout and typography
- Single column; `font-size ≥ 1rem` (no iOS zoom); `min-height: 48px`, 52px under `@media (pointer: coarse)`; `rem`, unitless `line-height`, logical properties; `scroll-padding` so the keyboard never covers the focused input or submit.

## Styling native controls
- `accent-color: var(--brand)` on `body` tints checkbox, radio, range and progress only; pair with `color-scheme: light dark` and a lighter shade in dark mode. Ensure contrast yourself (Safari and Android Chrome checkmark bugs).
- Visually-hidden recipe (never `display: none`): `position: absolute; clip-path: inset(50%); overflow: hidden; width: 1px; height: 1px; margin: -1px; padding: 0; border: 0; white-space: nowrap`.
- Autofilled: `input:autofill, input:-webkit-autofill` (not `:auto-fill`); background only via `box-shadow: 0 0 0 100vmax <color> inset`, plus a thicker border and an explicit `:autofill:focus-visible` outline.
- Support: `accent-color` Limited — Chrome 93, Edge 93, Firefox 92, Safari 26.2; fallback under `@supports not (accent-color: …)`: visually-hidden input + styled `+ span::before`. `:autofill` Limited — Chrome 110, Edge 110, Safari 15; unsupported Firefox; no JS fallback.

## Customizable select
- Opt in on both: `select, select::picker(select) { appearance: base-select }`. `<select>` may then hold `<button><selectedcontent></selectedcontent></button>` (`selectedcontent` mirrors the chosen option) and `<option>`s with SVG/images/divs — decorative SVG `aria-hidden="true"`, rich options get a concise `aria-label`.
- Parts: `::picker(select)` (top layer; `width: anchor-size(width)`), `::picker-icon`, `option::checkmark`, `option:checked` (bold + background, not colour alone), `:open`. No longest-option auto width (set one); opts out of the native mobile picker.
- Grid pickers: `select:open::picker(select) { display: grid }` — without `:open` the picker shows while closed. `role="grid"` inside the picker is invalid.
- Animate the picker with `transition: display/overlay … allow-discrete` + `@starting-style`; `interpolate-size: allow-keywords` for `height: auto`; none under `prefers-reduced-motion`.
- Support: Limited — Chrome 135, Edge 135, Safari 27; unsupported Firefox. Fallback is plain-text options (rich markup stripped) so option text must stand alone; detect with `CSS.supports('appearance', 'base-select')`; no polyfill.

## Switch
- `<input type="checkbox" switch>` with a `<label>`; submits the checkbox value; read `.checked` on `change`. Style the input itself (`accent-color`, `:focus-visible` outline).
- Support: Limited — Safari 17.4 only; unsupported Chrome, Edge, Firefox. `if (!('switch' in HTMLInputElement.prototype)) import('input-switch-polyfill')` — never unconditionally.

## Range slider
- Native `<input type="range">` + `<label>`, `min`/`max`/`step`/`value`; a formatted value lives in real DOM and `aria-valuetext`; no `::before`/`::after` on form controls.
- Colour only: `accent-color`. Full control: `appearance: none; margin: 0; border: 0`, then *separate* rule blocks for `::-webkit-slider-runnable-track`, `::-webkit-slider-thumb`, `::-moz-range-track`, `::-moz-range-progress`, `::-moz-range-thumb` — a comma-joined `-webkit-`/`-moz-` selector drops the whole rule.
- Fill: Firefox `::-moz-range-progress`; WebKit a two-stop `linear-gradient` track at `--p: calc(progress(var(--v), var(--min), var(--max)) * 100%)`, `--v` synced from `slider.value` on `input`.
- Support: `progress()` Baseline Newly available (since 2026-09-01) — fallback `@supports not (opacity: progress(1, 0, 100))` with `calc((v - min) / (max - min) * 100%)`. Typed `attr()` Limited — Chrome 133, Edge 133, Firefox 155; unsupported Safari — set `--min`/`--max` from JS.

## Fields that fit contents
- `field-sizing: content` on `input` with `width: auto; min-inline-size: 15ch; max-inline-size: 50ch`; on `textarea` with `height: auto; width: 100%`, `min-block-size: 3lh; max-block-size: 10lh`; on `select` with `max-inline-size: 50ch`.
- Explicit `width`/`height` override it — reset globals to `auto`; grid/flex stretch defeats it — `align-self: start`.
- Support: Baseline Newly available (since 2026-06-16); fixed sizing is the recommended fallback.

## Security and JS
- HTTPS; hidden CSRF token on POST/PUT/DELETE; sanitize before DOM insertion (DOMPurify); honeypot or CAPTCHA on open forms; no inline handlers under CSP; pay buttons state the amount ("Pay €100").
- AJAX: `e.preventDefault()` on `submit`, `new FormData(form)`; the form must still post without JS. No PII in analytics labels.
