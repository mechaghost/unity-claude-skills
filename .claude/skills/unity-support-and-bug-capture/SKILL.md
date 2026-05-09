---
name: unity-support-and-bug-capture
description: 'Use for Unity 6+ shipped-game support UX: in-game bug reports, support tickets, Helpshift/Zendesk/Freshdesk, log/device/screenshot capture, FAQ/chat, player/support ID display, account/data deletion flows. Not crash auto-capture or analytics.'
---

## When to use

Any time the game is approaching store submission or already live and there is no in-app bug-report flow, no customer-support intake, or no account-deletion entry point. Read `unity-best-practices` first. Cross-link `unity-crash-reporting` (parallel pipeline: same playerID, same breadcrumbs), `unity-auth-account-linking` (the playerID this skill displays + attaches), `unity-consent-att-gdpr` (deletion is one half of the consent contract), `unity-persistence` (log ring buffer, screenshot temp file), and `unity-patterns` (the manager singleton). `unity-store-shipping-pipeline` is where the Play Console "Account deletion" listing field gets filled.

## Why this is a launch requirement

Players hit bugs you didn't catch in QA. Without a one-tap report path they leave a 1-star review and uninstall — you never see the repro. Google Play's 2024 policy requires either an in-app account-deletion entry point OR a public web URL pre-declared in the listing; Apple requires the equivalent through the Privacy Policy. Customer support — refunds, missing IAP, lost progress, harassment reports, banned-account appeals — all need user-attributable context (playerID, device, recent actions) to resolve. This is day-one infrastructure, not polish.

## Pick a service

- **Helpshift** — in-app SDK with FAQ + chat + ticket UI, common in F2P. In-app FAQ deflects 30–50% of tickets. Ships its own consent dialog (coordinate with `unity-consent-att-gdpr`).
- **Zendesk** — web-ticket platform, simple email-style submission via API, no SDK weight. Good for studios already on Zendesk.
- **Freshdesk** — similar to Zendesk, cheaper at small scale.
- **Custom backend** — Cloud Function + signed S3 upload + a thin admin dashboard. Cheap for small studios; you eat the dashboard build cost.

## In-game bug report flow

Settings → "Report a Bug" → category dropdown (Gameplay / Crash / Purchase / Other) → description text field → "Attach screenshot" toggle (default on, auto-capture at submit) → Submit → server returns ticket ID, show toast "Ticket #1234 received". Don't require login — anonymous reports are still valuable. Auto-attach playerID; the user shouldn't have to type it.

For dev builds, gate a long-press on a debug button that fires a one-tap report with all auto-captured context and a "dev-report" tag.

## What to capture

- **Description** — user-typed.
- **Screenshot** — `ScreenCapture.CaptureScreenshotAsTexture()` AT submission time, not earlier. Captures the current state, including the report UI overlay (acceptable; if you need it without overlay, hide the panel for one frame, capture, restore). Downsample to 1280x720 max.
- **Recent logs** — last ~200KB from a ring buffer fed by `Application.logMessageReceived`. Gzip before upload.
- **Device info** — `SystemInfo.deviceModel`, `.operatingSystem`, `.systemMemorySize`, `.graphicsDeviceName`, `.processorType`, `.batteryLevel`.
- **App info** — `Application.version`, build number, platform, `Application.targetFrameRate`, current locale.
- **User context** — playerID (from `unity-auth-account-linking`), current scene name, current level/world, server-known currency totals, last 10 analytics events from a parallel ring buffer.
- **Network state** — `Application.internetReachability`, region/store country.
- **Bundle** — JSON metadata + screenshot PNG + gzipped log, posted as multipart form-data or zipped to a signed upload URL.

## Account deletion (GDPR + Play 2024)

In-app entry: Settings → Account → **Delete My Account**. Show a clear warning ("This will permanently delete your progress, purchases, and cloud save. This cannot be undone."), then a confirmation step (typed "DELETE" or a second tap) before submission.

Server flow: client calls `POST /api/account/delete` with the playerID + auth token → server enqueues a deletion job → 30-day grace period per GDPR (user can cancel by signing in again) → on day 30, anonymize/delete the user record, cloud save, and analytics events. IAP receipts are typically retained under legal-retention exemption (tax/audit). Email a confirmation at submission and at completion.

Public web URL alternative: `https://yourstudio.com/data-deletion` — a form that takes player ID + email and queues the same backend job. Required if the in-app entry isn't available pre-login.

**No-backend fallback**: if you have no backend, use the public web URL form route exclusively (`https://yourstudio.com/data-deletion` with a Google Form, Tally, or Typeform behind it that emails you). Required by Google Play 2024 listing field. The in-app endpoint is optional when the public URL is provided.

GDPR rights beyond deletion: **data export** (machine-readable JSON or CSV — HTML/PDF doesn't qualify) and **rectification** (edit-profile screens for name, email, etc.). Wire both behind the same Settings → Account screen.

## Player support ID

Display the playerID in Settings ("Player ID: 4F2A-9X8B"). Same value the auth system issues; format it for human typing — uppercase hex grouped in 4-char blocks, no ambiguous characters (`0/O`, `1/I`). Provide a Copy button. Customer support agents look up tickets by this. NEVER include PII (email, name) in this string.

## Common patterns

- **BugReportManager singleton** (cross-link `unity-patterns`) — DontDestroyOnLoad component subscribed to `Application.logMessageReceived` from boot, maintains the rolling 200KB log buffer and the analytics-event ring. Exposes `SubmitReport(category, description, attachScreenshot)`.
- **One-tap dev report** — long-press a debug button (dev builds only) → submits everything auto-captured + a "dev" tag → "Report sent" toast.
- **Helpshift in-app FAQ** — wire FAQ tags by category (Purchase / Gameplay / Crash); a "Did this help?" pre-form deflects 30–50% of tickets before the user files one.
- **Customer support tooling** — admin dashboard with refund button, gem grant, account flag, ban, view-cloud-save. Lock behind 2FA and per-action audit log. CS agents look up by player support ID, never by email alone.
- **Auto-attach playerID** — never make the user type it. They'll get it wrong.

## Gotchas

- **PII in logs** — if signup logs the user's email, your dump leaks PII = GDPR problem. Sanitize before send (regex-strip emails, tokens, payment fragments). Test the dump on your own account before shipping.
- **Payload size** — full-res screenshot + raw log can exceed 10MB. Downsample to 1280x720, JPEG quality 85, gzip the log. Upload over Wi-Fi only when payload > 1MB.
- **WebGL** — no `Application.persistentDataPath` for log files; keep the buffer in-memory only and post directly. No `System.IO.File` for the temp screenshot — encode to PNG bytes in memory.
- **Helpshift consent dialog** — Helpshift's SDK ships its own consent UI; coordinate with `unity-consent-att-gdpr` so the user doesn't see two consent prompts.
- **Anonymization vs hard delete** — explicitly tell the user which one you do. Some jurisdictions (EU, California under CPRA) require true deletion, not just anonymization. Document your retention policy in the privacy policy.
- **Data export format** — must be machine-readable. JSON or CSV qualifies; an HTML page or PDF does not.
- **Refund flow confusion** — refunds via support backend bypass the platform store refund. Document who handles what (Apple/Google handle store-purchase refunds; you handle in-game grants). CS agents need a flowchart.
- **Open S3 bucket** — never upload screenshots/logs to an unauthenticated bucket. Use signed PUT URLs from the server, short TTL (5 min), one URL per upload.
- **Play Console "Account deletion" listing field** — added in 2024. Missing it = listing rejection. Fill the in-app deep-link AND/OR the public web URL during store submission (cross-link `unity-store-shipping-pipeline`).
- **Don't capture a screenshot before submit** — captures stale state. Capture in the same frame as Submit press.

## Verification

- Submit a bug report from in-game on a real device → ticket appears in the support backend within ~5 seconds with screenshot, log, device info, and playerID attached.
- Trigger a known error (e.g. force a `Debug.LogException`) before submitting → error line appears in the captured log.
- Account deletion: submit from Settings → confirmation email arrives → wait the grace period → account record anonymized in DB, cloud save gone, analytics events scrubbed, IAP receipts retained per policy.
- Public web deletion URL responds 200, form submits, user receives confirmation email.
- Player ID in Settings is copyable and matches the server's playerID format exactly.
- Sanitization: search the submitted dump for `@`, `password`, payment-token patterns — none should appear.
- Helpshift FAQ deflection (if used): instrument "FAQ shown" vs "Ticket filed" and confirm > 30% deflection rate post-launch.
- Play Console listing has the Account Deletion field populated; pre-submission validator passes.
