---
name: unity-anti-cheat-iap-fraud
description: Use when defending a Unity F2P game against cheating, IAP fraud, and tampering — anti-cheat, anticheat, IAP fraud, receipt forgery, jailbroken device, rooted device, root detection, jailbreak detection, EasyAntiCheat, BattlEye, Beebyte, IL2CPP obfuscation, code obfuscation, server-authoritative, server validation, leaderboard fraud, currency fraud, modded client, hacked client, packet sniffing, certificate pinning, anti-tamper, integrity check, signature verification, addressables signing, content catalog signing, hash check. Unity 6 / 2023.2 LTS, URP-only, new Input System only. NOT for IAP basics (use unity-iap), NOT for crash reporting (use unity-crash-reporting).
---

# Unity Anti-Cheat & IAP Fraud Defense

Defense in depth for F2P games. None of this is absolute — determined attackers bypass any client. The goal is to raise cost, catch the casual majority, and make server-side the source of truth for anything that matters.

## When to use

You ship an online or live-service Unity title and worry about modded clients, forged receipts, leaderboard cheating, or asset tampering. Single-player offline games need very little of this; pure cosmetic-only economies need less. Anything that touches real money or competitive ranking needs all of it.

## Threat model

- **Casual cheaters** — cheat menus, GameGuardian, Cheat Engine, save editors. Defended by basic obfuscation, integrity checks, and PlayerPrefs hygiene.
- **Determined attackers** — Frida, IDA Pro, Ghidra, custom dynamic instrumentation. Cannot be fully stopped on the client. Mitigate via server authority.
- **Receipt fraudsters** — forged Apple/Google receipts to claim purchases without paying. Defended by server-side receipt validation against the store's API.
- **Modded clients** — republished APKs/IPAs with infinite currency or unlocked content. Defended by server-authoritative state and signed addressables.

## Server-authoritative design

The only real defense for online games. If the client owns it, the client cheats it.

- **Currency totals live on the server**. Client shows a cached value. Spending = client requests, server validates and returns the new total.
- **Combat results** — server simulates or validates outcomes. Client predicts for responsiveness, server reconciles.
- **Inventory** — server-canonical, client mirrors.
- **Single-player** — server-side is optional, but cloud save validation can catch impossible states ("how did this player gain 1M gems in 10 seconds?").

## IAP receipt validation (server-side)

See also unity-iap for the basic IAP flow.

- Client → server: send `receipt`, `productID`, `transactionID`.
- Server → store:
  - **Apple — App Store Server API**. The 21007-fallback dance is `verifyReceipt` behavior, NOT App Store Server API. ASSA uses **separate base URLs** by environment: `https://api.storekit.itunes.apple.com` (production) and `https://api.storekit-stage.itunes.apple.com` (sandbox). The client (or, on webhooks, the notification's `environment` field) tells you which base URL to hit — there is no retry-on-21007 path. Authenticate with an ES256 JWT (.p8 key); see `unity-iap` for the JWT contract.
  - **Google**: Android Publisher API — full paths `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{token}` (consumables / non-consumables) and `.../purchases/subscriptionsv2/tokens/{token}` (subscriptions).
- Server confirms `productID`, `transactionID`, amount, environment, refund/cancellation status.
- **Idempotency** — key grants by `originalTransactionId` (Apple) / `purchaseToken` (Google). Unique-indexed; second arrival no-ops to the existing entitlement. Detail in `unity-iap`.
- **Webhooks** — subscribe to Apple Server Notifications V2 + Google Real-time Developer Notifications (Pub/Sub) for refund/chargeback events. Revoke entitlements on refund. Verify the JWS cert chain on Apple webhooks; dedupe Google webhooks by Pub/Sub `messageId`. Detail in `unity-iap`.

## Currency / score validation

- Server tracks expected gain rate. 1000 gems/sec on a tap-to-earn game = flag for review.
- Leaderboard submissions: include a cryptographic seed of the run + replay data. Server replays and verifies the score is achievable on that seed.
- Heuristic detection: top 0.1% scores reviewed by automation; physically impossible scores auto-banned.

## Addressables catalog signing

A modified content catalog can swap a `weapon_X` prefab for `weapon_X_with_infinite_damage`. Defend by signing.

- Server publishes a signed manifest containing the expected catalog hash.
- App boots → fetches signed manifest → manifest references catalog by hash → catalog loads only if hash matches.
- Verify ahead of `Addressables.InitializeAsync` so a tampered catalog never reaches `LoadAssetAsync`.
- See unity-addressables for content delivery patterns and unity-build for post-build signing.

## IL2CPP obfuscation

IL2CPP build configuration (scripting backend, code stripping, link.xml) lives in `unity-build`. This skill adds the obfuscation overlay on top: Beebyte's Obfuscator (or equivalent) for symbol renaming, plus string encryption and control-flow obfuscation for sensitive paths (API URLs, validation endpoints, anti-cheat hooks). Buys time against static analysis; does not stop runtime instrumentation (Frida).

## Root / jailbreak detection

- **Android indicators** — `/system/app/Superuser.apk`, executable `su` on PATH, common Magisk paths, `test-keys` build tag.
- **iOS indicators** — `/private/var/lib/cydia`, `/Applications/Cydia.app`, ability to fork(), writable `/private/`.
- **Plugins** — NCheck, ACTk (Anti-Cheat Toolkit) wrap the detection logic with regular updates.
- **Action** — gate online features (leaderboards, IAP, ranked) on rooted devices; warn the user; allow offline play.
- Don't outright ban — root users may be legitimate developers, accessibility tool users, or QA.

**Filesystem checks alone are defeated by Magisk Hide / Shamiko / similar — treat them as a low-cost first gate, not a real defense.** The production-grade defense is platform attestation:

- **Android — Play Integrity API** (modern replacement for SafetyNet Attestation, which Google deprecated in 2024 with shutdown phased through 2025). Client requests a token from Play services; Google returns a signed JWT that attests to app integrity (matches Play-distributed signature), device integrity (unmodified Android), and account licensing. Server verifies the JWT against Google's keys and rejects tampered devices on sensitive paths (IAP grant, leaderboard submit).
- **iOS — DeviceCheck / App Attest**. App Attest (iOS 14+) is the equivalent: the device generates a hardware-backed key pair and signs server challenges; your server verifies via Apple's attestation roots. Use it on the same sensitive paths.

Both systems fail closed: gate the request server-side on a fresh attestation, not just at boot.

## Network protection

- **Certificate pinning** — pin the server's public key in the client; reject MITM proxies (Charles, mitmproxy). Adds 1-2 days to an attacker's setup, not weeks. Ship a cert update path before you need it.
  - **Pin both current AND backup**. Always ship the client knowing two pins: the current cert (or its SPKI) and a backup. When the cert rotates, the backup pin keeps the install alive while you push a build that learns the next backup. Without a backup pin, cert renewal becomes a self-DoS event — every install on the network bricks the moment the cert flips.
  - **Pin the SPKI (Subject Public Key Info), not the cert**, when you can. Pinning the public key survives cert renewal as long as you reuse the same key on rotation — no client update needed.
  - **Rotation cadence**: leaf certs are typically 1-year (matches public CA terms); intermediates are longer. Pinning the leaf forces yearly client updates; pinning intermediate or SPKI lets you rotate the leaf transparently.
- **Encrypted payloads** — TLS is mandatory. Add app-level encryption (nonce + HMAC) on sensitive endpoints to defeat replay attacks even if pinning is bypassed.
- **Rate limiting** — server-side per-user. Block brute-force currency or progression requests.

## Player reporting

- In-game "Report Player" → backend reviews replay data, ban list, anomaly heuristics.
- Don't auto-ban from reports alone. False positives are catastrophic for retention. Use reports as a signal that triggers automated review or human review for high-tier accounts.

## Common patterns

- **All currency on server, client just displays**.
- **IAP grants entitlements server-side**; client shows a pending state until server confirms.
- **Leaderboard with replay** — client uploads replay file with score; server simulates and validates.
- **Save sanity** — cloud save validates against the server-known state; rejects impossible deltas.
- **A/B test cheat detection** — silent ban / shadow ban for confirmed cheaters; metrics show retention impact and false-positive rate before you commit. See unity-ab-testing.

## Gotchas

- Client-side anti-cheat alone = rubber chicken. Determined attackers bypass everything.
- False positives = banned legit players + bad PR. Always have human review for permanent bans.
- IL2CPP obfuscation breaks reflection / `JsonUtility` on private fields if not configured. Test thoroughly with realistic save data.
- Apple sandbox receipts have a different format than production; handle both server-side, never trust the client to tell you which.
- Refund webhooks may arrive **hours** after the refund. Design for eventual consistency — entitlement revocation can lag.
- Certificate pinning breaks when your server cert rotates. Ship a cert update path *before* you need it; otherwise a routine rotation bricks every install.
- Storing private keys / secrets in client code = exposed. Anything sensitive must be server-side.
- `PlayerPrefs` is plaintext. Never store currency / unlock state there for online-required games. See unity-persistence.
- Unity Ads + IAP test mode shipped to production = leak / fraud channel. Strip in `OnPostprocessBuild`.
- Integrity checks delayed → user gains 30s of cheating before disconnect. Balance UX against strictness.
- Banning by hardware ID is fragile (changes on factory reset, spoofed easily). Ban by account + payment method. See unity-auth-account-linking.

## Verification

- **Forged receipt test** — synthesize a receipt or replay a known-good one with a tampered productID → server rejects.
- **Currency cheat** — edit local save → server reads, detects mismatch → corrects to server canonical.
- **Rooted device test** — launch on rooted Android / jailbroken iOS → online features gated, offline still plays, no crash.
- **Catalog tampering** — swap an addressable file → hash mismatch → load fails safely with a user-visible "content corrupted" message.
- **Cert pinning** — route through MITM proxy (mitmproxy with custom CA) → connection refused, not silently downgraded.
- **`LogAssert`** clean of integrity-check warnings during normal play. False positives in test runs predict false positives in production.

See also: unity-iap (basic IAP flow), unity-addressables (content delivery), unity-build (IL2CPP build, post-build signing), unity-auth-account-linking (server identity), unity-best-practices.
