<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/privacy/ (1 guide)
     at 4f2b13e25c5815b3f080ca0d983e828d96561a0f, Apache-2.0 — see ../NOTICE.md -->

# Privacy

Open for: forms and data collection, cookies, logging, third-party embeds and sign-in, permission prompts, privacy headers, fingerprinting, data-rights flows.

## Principles
- Privacy-protective by default; no consent-dialog fatigue.
- Collect only what the task needs; delete once the purpose is fulfilled.
- Never reuse data for another purpose (security check -> marketing) without fresh consent.
- Say why data is collected, where it goes, how long it is kept.
- Act as the user's agent, not a third party's.

## Data minimization
- Lowest granularity needed: an age-bracket `<select>` (18-34, 35-49, 50+), not a date of birth.
- Offer guest checkout; never force account creation.
- Fuzz or add noise (differential privacy) for aggregate statistics.
- Never collect speculatively "just in case".

## Transparency
- Explain why a field is requested inline, next to the input (`<a href="#phone-help">` + `<aside>`), not in a policy.
- Give reason and context before requesting powerful permissions (camera, location).
- Prefer the declarative Page Embedded Permission Control `<permission>` element where supported, with a button fallback:
```html
<permission type="geolocation" onpromptdismiss="updateMap()">
  <button onclick="navigator.geolocation.getCurrentPosition(updateMap)">Use my location</button>
</permission>
```
- On logout send `Clear-Site-Data: "*"`. If it clears cache, send it from a subresource, not the main navigation response (blocks rendering on slow devices).
- Opt-out and deletion as easy as sign-up; no dark patterns.

## Cookies and storage
- Session cookie: `Secure; HttpOnly; SameSite=Lax`.
- 1:1 embeds with no cross-site state use CHIPS: `SameSite=None; Secure; Path=/; Partitioned; HttpOnly`.
- Never rely on unpartitioned `SameSite=None` cookies.
- Never put tokens or PII in `localStorage`; any embedded script reads it.
- Scrub PII from logs; automated masking for emails, tokens, IDs.
- Rate-limit endpoints exposing user data (search, profile views) against scraping. See security.md.

## Third parties
- Audit network requests (DevTools, HAR) for what third parties collect; popularity is not safety.
- No third-party scripts on sensitive pages (checkout, health) unless strictly necessary.
- Heavy embeds (YouTube, TikTok): façade — static thumbnail, iframe only on click.
- Privacy-preserving embed hosts, e.g. `youtube-nocookie.com/embed/<id>`.
- Social sharing: a static intent link (`<a href="https://x.com/intent/tweet?…" rel="noopener" target="_blank">`), not the SDK.
- Sign-in via FedCM so the IdP cannot track the RP before consent:
```js
const credential = await navigator.credentials.get({
  identity: { providers: [{ configURL, clientId, nonce }] }
});
```

## Headers
- `Permissions-Policy: geolocation=(), camera=(), microphone=(), accelerometer=()` — off by default, enable only where required.
- `Referrer-Policy: strict-origin-when-cross-origin` — stop URL parameters leaking to third parties.

## Fingerprinting
- Feature detection (`'IntersectionObserver' in window`), never UA sniffing (`navigator.userAgent.includes("Chrome/100")`).
- Device targeting: User-Agent Client Hints — `if (navigator.userAgentData)` then `getHighEntropyValues(["platformVersion", "architecture"])`.
- Never fingerprint via canvas rendering, font lists, or audio/video device enumeration.
- Never depend on the full granularity of `navigator.userAgent`.

## Data rights
- Provide access to all collected data, correction, and automated (or easy manual) deletion.
- Automated sign-up implies automated deletion; never route erasure through support.
- Never deny non-dependent services to users who exercise their rights.
