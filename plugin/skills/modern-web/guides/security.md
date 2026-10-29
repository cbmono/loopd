<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/security/ (17 guides)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Client-side security

Open for: DOM XSS sinks, CSP, Trusted Types, HTML sanitising, origin checks, cookies, security and isolation headers, SRI, outbound allowlists, WebCrypto, passkeys/WebAuthn, immediate sign-in, email verification. Browser defences only; the server still owns authz and input validation.

## Code hygiene (do first)
- `textContent` over `innerHTML`; never `innerHTML`/`setHTMLUnsafe` with untrusted input. Grep: `innerHTML`, `outerHTML`, `document.write`, `eval`, string `setTimeout`, `script.src`.
- Cookies: `__Host-` prefix (needs `Secure`, `Path=/`, no `Domain`) else `__Secure-`; `HttpOnly`; explicit `SameSite=Lax`; iframe-embedded apps `SameSite=None; Secure; Partitioned` (unpartitioned `None` is being blocked).
- `X-Frame-Options: SAMEORIGIN` (or `DENY`) plus CSP `frame-ancestors 'self'`.
- `postMessage`: strict-equality `event.origin` check (no `*`, no substring); explicit target origin on send; validate payload fields before any sink.
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`; start at `max-age=300` (a wrong long value locks users out until it expires).

## Rollout: inventory, report-only, enforce
- Inventory headers (server, CDN, meta), inline scripts/styles, third-party script origins, popups (COOP), embeds (COEP/CORP/`frame-ancestors`), features used (`Permissions-Policy`), unversioned scripts (SRI), webhooks/SSO (Fetch Metadata).
- Dry-run with `Content-Security-Policy-Report-Only` (also `Cross-Origin-Opener-Policy-`, `Cross-Origin-Embedder-Policy-`, `Document-Policy-Report-Only`); declare `Reporting-Endpoints: default="…"` and name it in `report-to` (`default` also gets deprecation/crash reports). Run on real traffic for weeks.
- `'report-sample'` in `script-src` (first 40 chars of the violation). Ignore noise (old browsers, extensions, crawlers, low volume); strip PII/tokens at the edge.
- Triage: inline scripts need nonces (SSR) or hashes (static); third-party loaders need `'strict-dynamic'` + nonce, never a domain allowlist; Trusted Types hits need the sink fixed or a policy.

## Content Security Policy
```http
Reporting-Endpoints: main="https://reports.example/main"
Content-Security-Policy: script-src 'nonce-{RANDOM}' 'strict-dynamic' 'report-sample'; object-src 'none'; base-uri 'none'; frame-ancestors 'self'; require-trusted-types-for 'script'; report-to main
```
- All of the above are mandatory; `form-action 'self'` optional. Keep `report-to` when enforcing.
- Fresh nonce per request (`crypto.getRandomValues(new Uint8Array(16))`, base64), passed to the template so only authored `<script nonce>` tags get it; static HTML uses `sha256-` hashes instead.
- Compat ladder `'strict-dynamic'`, `https:`, `'unsafe-inline'`: each browser honours the strictest token it knows.
- Never a scheme/domain allowlist as primary `script-src` (open redirects and JSONP bypass it); never regex-stamp nonces onto rendered HTML (it nonces injected `<script>` too). `<meta http-equiv>` CSP: first child of `<head>`, weaker than the header.

## Trusted Types
- Enforce with `require-trusted-types-for 'script'`; limit names with `trusted-types sanitize-html dompurify default` (`dompurify` when delegating to `DOMPurify.sanitize()`, `default` while migrating). Unlisted names and raw-string sink writes throw.
- Sinks: `innerHTML`, `outerHTML`, `document.write()`, `setHTMLUnsafe()`, `parseHTMLUnsafe()`, `<script>` text, `eval()`, `<script src>`, `Worker()`. `setHTML()`, `parseHTML()`, `textContent` need no policy.
- `trustedTypes.createPolicy('sanitize-html', { createHTML: s => DOMPurify.sanitize(s, { RETURN_TRUSTED_TYPE: false }) })`; never pass-through `s => s`. Entity escaping is not sanitising; never interpolate it into attributes or URLs (`javascript:` survives).
- Migrate via a temporary `default` policy that warns and sanitises; the framework and every sink-writing library must emit `TrustedHTML`/`TrustedScript`; report-only, then enforce at zero violations.
- Support: Baseline Newly available (since 2026-02-24). Tinyfill: `window.trustedTypes ??= { createPolicy: (n, rules) => rules }`.

## Sanitise untrusted HTML
- `el.setHTML(html)` parses, sanitises and inserts; restrict with `{ sanitizer: { elements: ['p','b'], attributes: ['class'], replaceWithChildrenElements: ['div'] } }` (or `new Sanitizer(config)`). Disallowed elements go with their content unless listed in `replaceWithChildrenElements`. A config only tightens the XSS-safe default; unsafe markup needs `setHTMLUnsafe`/`parseHTMLUnsafe`.
- `Document.parseHTML(raw)` returns a sanitised `Document`; move its nodes (`replaceChildren(...doc.body.childNodes)`), never re-parse via `innerHTML` (mXSS). Sanitise server-side too when content renders elsewhere, with aligned rules.
- Support: Limited — Chrome 146, Edge 146, Firefox 148; unsupported in Safari. Detect `'setHTML' in Element.prototype`; else lazy `import('dompurify')` with `ALLOWED_TAGS: [...elements, '#text']`, `ALLOWED_ATTR`, `ALLOW_ARIA_ATTR: false`, `ALLOW_DATA_ATTR: false`, `KEEP_CONTENT: false` to match native; under Trusted Types add `RETURN_TRUSTED_TYPE: true` and allow the `dompurify` policy.

## Validate origins
- `Origin.from(x).isSameOrigin(trusted)` for privilege boundaries (a sibling subdomain is a different origin); `isSameSite()` for `?returnTo=` redirects and internal-link checks: schemeful, Public-Suffix-List aware (`a.github.io` vs `b.github.io` is false).
- Both sides must be `Origin` instances. `Origin.from()` takes URL strings, `URL`, `<a>`, `self`, browser-dispatched `MessageEvent`; `Location`, `Document`, `Request` throw (pass `self` or `request.url`). Invalid strings and `'null'` throw: wrap in `try/catch` returning `false`.
- Opaque origins (`sandbox="allow-scripts"`, `data:`): `origin.opaque === true`; `Origin.from(event)` keeps identity so two sandboxed frames differ; `new Origin()` is a deny-all sentinel until a widget's origin is pinned on `init`.
- Never `startsWith`/`includes`/`endsWith`/`split('.')`; never compare two runtime origin strings without rejecting `'null'`.
- Support: Limited — Chrome 145, Edge 145, Safari 26.5; unsupported in Firefox. Fallback: `new URL()`; same-origin = `u.origin !== 'null' && u.origin === trusted.origin`; same-site only against a private domain you control; sandboxed frames: check `event.source` or use a `MessageChannel` port.

## Isolation headers
- `Cross-Origin-Opener-Policy: same-origin-allow-popups` keeps app-initiated OAuth/payment popups; `same-origin` only once nothing needs cross-origin `window.opener`. Skip if you are an OAuth provider or payment processor.
- `Cross-Origin-Resource-Policy: same-origin` for app data/scripts; `same-site` across subdomains; `cross-origin` only for embeddable/CDN assets.
- Cross-origin isolation only for `SharedArrayBuffer`: `Document-Isolation-Policy: isolate-and-credentialless` (Chrome 142+; `isolate-and-require-corp` stricter) or cross-browser COOP `same-origin` + `Cross-Origin-Embedder-Policy: require-corp` (every subresource needs CORP or fails to load).
- Fetch Metadata: reject `Sec-Fetch-Site: cross-site` on non-navigation endpoints before auth; allow `same-origin`/`same-site`/`none`, cross-site `GET` with `Sec-Fetch-Mode: navigate` unless `Sec-Fetch-Dest` is `object`/`embed`, and requests without the header. Add `Vary: Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site`. Drop `same-site` if a subdomain hosts untrusted content.

## Companion headers
- `X-Content-Type-Options: nosniff` (serve correct `Content-Type` everywhere); `Referrer-Policy: strict-origin-when-cross-origin`; on logout `Clear-Site-Data: "cookies", "storage", "cache"`.
- `Permissions-Policy: camera=(), geolocation=(), microphone=(), focus-without-user-activation=()`; delegate to iframes via the `allow` attribute too; blocked delegated features fail silently in widgets, so audit first.
- CORS is a grant, not a defence: echo a validated `Origin` into `Access-Control-Allow-Origin`; `*` with `Access-Control-Allow-Credentials: true` is rejected; answer `OPTIONS` preflights first.

## External subresources (SRI, CORS, referrer)
- Digests at build time from known-good bytes (`openssl dgst -sha384 -binary f.js | openssl base64 -A`), never from the live URL; `sha384-<base64>` (`sha512-`/`sha256-` also); space-separate several when an endpoint serves variants. Pin immutable versioned URLs; a mutable tag (`latest`, vendor analytics) gets no `integrity`, only nonce + `'strict-dynamic'` or an iframe sandbox.
- On `<script>` and `<link rel="stylesheet|preload|modulepreload">` set `integrity`, `crossorigin="anonymous"` (required with cross-origin `integrity`; an opaque `no-cors` response fails the check) and `referrerpolicy="no-referrer"`; the CDN must send `Access-Control-Allow-Origin`. `fetch()` takes `integrity`, `mode: 'cors'`, `credentials: 'omit'`, `referrerPolicy`.
- CSS `url("…" cross-origin(anonymous) referrer-policy(no-referrer) integrity("sha384-…"))` on `@import`, `@font-face src`, `background-image`: quoted URL, each modifier once; `background-image` and `@import` default to `no-cors`, so always pair `integrity()` with `cross-origin(anonymous)`.
- Support: Limited — `cross-origin()`/`referrer-policy()`: Chrome 150, Edge 150, Safari 26.2, unsupported in Firefox; `integrity()`: Chrome 150, Edge 150 only. Fallback: `<link rel="stylesheet">` over `@import`; cascade separate declarations (plain `url()`, then with modifiers, then with `integrity()`); never an unverified `url()` in the same comma-separated `@font-face src` (a failed check falls back to it).

## Restrict outbound connections
- `Connection-Allowlist: (response-origin "https://api.example.com" "https://*.cdn.example.com/*"); report-to=conn`: one RFC 9651 inner list, unquoted `response-origin` and parameters, double-quoted `URLPattern`s, no commas. Malformed fails closed (blocks all); `()` revokes all network. Covers fetch, subresources, `sendBeacon`, navigations, prefetch/preconnect, WebSocket, WebTransport, WebRTC.
- No trailing slash on origin-only patterns (`new URL(o).href` adds one, matching only `/`); write `ws(s)://` as `http(s)://`; no regex groups or scheme-less paths; include navigation targets (OAuth, checkout). Defaults block every `3xx` (even same-origin) and WebRTC: `; redirects=allow`, `; webrtc=allow`. Catch `TypeError` on `fetch()`.
- Honoured only on `Sec-Fetch-Dest` `document|iframe|worker|sharedworker|serviceworker` responses (add `Vary: Sec-Fetch-Dest`); a service worker's list is a superset of its clients'. `Connection-Allowlist-Report-Only` may run beside it.
- Support: Limited — Chrome 152, Edge 152; unsupported in Firefox and Safari. Not polyfillable; pair with CSP `default-src 'self'; connect-src 'self' https://api.example.com wss://rt.example.com; form-action 'self'; worker-src 'self'; object-src 'none'` (`default-src` does not cover `form-action`; list `wss://` explicitly).

## WebCrypto
- AEAD: `'AES-GCM'` (`{ name, length: 256 }`) or `'ChaCha20-Poly1305'` (fixed 256-bit key, no `length`); fresh random 12-byte `iv` per `encrypt()`, never reuse `(iv, key)`; bind metadata via `additionalData`. Key exchange: `'MLKEM768-X25519'` with `encapsulateKey()`/`decapsulateKey()` (shared key as `'AES-GCM'`, `'ChaCha20-Poly1305'` or `'HKDF'`). Signatures: `'ML-DSA-65'`, `sign({ name, context })` with a ≤255-byte `context`; no `hash` param (nor for `'Ed25519'`).
- Keys: `generateKey(name, false, usages)`; persist non-extractable `CryptoKey`s in IndexedDB by structured clone. Modern algorithms reject `'raw'`: use `'raw-public'`, `'raw-seed'` (one usage only), `'raw-secret'`, `'jwk'`; `getPublicKey(privateKey, usages)` recovers a public key.
- Support: Web Cryptography Baseline Widely available (since 2017-09-19); X25519 `deriveBits` Baseline Newly available (since 2025-02-06); Ed25519 `sign` Baseline Newly available (since 2025-05-29). Detect post-quantum via static `SubtleCrypto.supports('encapsulateKey', 'MLKEM768-X25519', 'ChaCha20-Poly1305')` / `SubtleCrypto.supports('sign', 'ML-DSA-65')` (`crypto.subtle.supports` is undefined); fall back to `'X25519'` + `'HKDF'` + `'AES-GCM'` and `'Ed25519'` with `'raw'` keys (they ignore `context`; length-prefix it into the payload).

## Passkeys
- HTTPS (or `http://localhost`); `rpId` equals or is a registrable suffix of the origin host, else `SecurityError`. Server uses a vetted FIDO2 library (SimpleWebAuthn, py_webauthn, go-webauthn, java-webauthn-server, fido2-net-lib); the client calls `navigator.credentials.*` directly.
- Server: high-entropy challenge in the session (Base64URL); `pubKeyCredParams` `alg: -7`, `-257`; store `id`, public key, `counter`, `transports`, `credentialDeviceType`, `credentialBackedUp`, `aaguid`. AAGUID is a UX hint only (provider name/icon from the community registry; all-zero is "Unknown passkey provider").
- Client: `import 'webauthn-polyfills'`; `PublicKeyCredential.parseCreationOptionsFromJSON()`/`parseRequestOptionsFromJSON()` in, `credential.toJSON()` out (Baseline Newly available since 2025-03-31); gate UI on `PublicKeyCredential.getClientCapabilities()` (Baseline Newly available since 2025-02-06).
- Registration: `authenticatorSelection: { residentKey: 'required', requireResidentKey: true, userVerification: 'preferred' | 'required' }`; `excludeCredentials` = existing IDs with `transports`; `authenticatorAttachment: 'platform'` for post-login promotion, omitted in settings so security keys work; hide "Create passkey" unless `passkeyPlatformAuthenticator` and `conditionalGet`. `InvalidStateError` = already registered; `NotAllowedError` = cancelled. Server checks the UP flag; with `'preferred'` verify with `requireUserVerification: false`.
- Authentication: `<input autocomplete="username webauthn" autofocus>`; on load, if `capabilities.conditionalGet`, `navigator.credentials.get({ publicKey, mediation: 'conditional', signal })` with `allowCredentials: []`; abort that controller before a button-triggered `get()`, re-arm after a cancel. Keep the requested `userVerification` in the session, never from the client. Unknown credential ID: HTTP `404`.
- Conditional create: only right after a full password sign-in (all MFA done; not magic link/OTP/federation); abort the conditional-get controller; require `capabilities.conditionalCreate`; `navigator.credentials.create({ publicKey, mediation: 'conditional' })` with `excludeCredentials`; swallow `InvalidStateError`/`NotAllowedError`/`AbortError`; server uses `requireUserPresence: false` for this flow only.
- Signal API (Limited — Chrome 132, Edge 132, Safari 26; unsupported in Firefox; feature-detect; IDs are Base64URL strings, never `rawId`): `signalUnknownCredential({ rpId, credentialId })` when registration verification fails or login returns `404` while unauthenticated; `signalAllAcceptedCredentials({ rpId, userId, allAcceptedCredentialIds })` on management-page load and after each delete; `signalCurrentUserDetails({ rpId, userId, name, displayName })` after an account rename (a passkey nickname rename is server-only).
- Management: list/rename/delete scoped to the signed-in user (`404` otherwise); show provider icon/name, registered and last-used dates. Reauthentication: `allowCredentials` = the signed-in user's descriptors (empty regresses to discoverable); reject an assertion whose stored `passkeyUserId !== req.user.id`; `404` to `signalUnknownCredential`.

## Quick sign-ins (immediate UI)
- `navigator.credentials.get({ password: true, publicKey, uiMode: 'immediate' })` in a click handler (never on load): local account chooser, or an instant `NotAllowedError` when no local passkey/password exists, in Incognito, or on dismissal; then continue to the normal sign-in page or guest checkout with a return URL.
- No non-empty `allowCredentials`, no `signal` (abort any conditional-UI controller first). Not on the dedicated sign-in page (it suppresses QR/security keys), not for step-up reauth.
- Branch on `cred.type`: `'public-key'` posts `toJSON()` to the assertion endpoint (`404` to `signalUnknownCredential`); `'password'` posts `{ username: cred.id, password: cred.password }`.
- Check `capabilities.immediateGet` first; browsers that ignore `uiMode` open a blocking modal QR dialog. `password: true` support: Limited — Chrome 60, Edge 79; unsupported in Firefox and Safari.

## Verify email ownership
- Origin Trial only (`Origin-Trial` header or `<meta http-equiv="origin-trial">`). `<input type="hidden" name="token" nonce="…" autocomplete="email-verification-token">` in the same `<form>` as `<input autocomplete="email">`; the browser fills an `EVT~KB-JWT` when the mail provider participates, else submits empty.
- Nonce: at least 128 bits per render, in server-side session state (not a cookie), page served `Cache-Control: no-store`, consumed atomically on POST. Verify server-side only with SD-JWT/JOSE libraries: `email_verified === true`, case-insensitive email match, `_email-verification.<domain>` DNS TXT `iss=` matches `iss` before fetching `${iss}/.well-known/email-verification`, algorithms `['Ed25519','EdDSA','ES256']`, `maxTokenAge '5m'`, `keyBindingNonce` + `expectedKeyBindingAudience` passed to `sdJwt.verify()`; trial every JWKS key when `kid` is absent (Gmail).
- Empty token or any failure: standard OTP/magic link, never block sign-up.
