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
  - **Apple**: App Store Server API. Hit the production endpoint first; if it returns `21007`, retry against sandbox (Apple's official fallback).
  - **Google**: Google Play Developer API `purchases.products.get` / `purchases.subscriptions.get`.
- Server confirms `productID`, `transactionID`, amount, sandbox flag, refund/cancellation status.
- **Idempotency** — store `transactionID` and never grant the same purchase twice.
- **Webhooks** — subscribe to Apple Server Notifications V2 + Google Real-time Developer Notifications for refund/chargeback events. Revoke entitlements on refund.

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

- **Symbol renaming** — Beebyte's Obfuscator (or similar) renames methods/types in the IL2CPP build. Static analysis becomes painful.
- **String encryption** — encrypt sensitive strings (API URLs, encryption keys, validation endpoints) at compile time, decrypt at runtime.
- **Limits** — does not stop dynamic analysis (Frida hooks at runtime). Buys time, that's all.
- See unity-build for IL2CPP build configuration.

## Root / jailbreak detection

- **Android indicators** — `/system/app/Superuser.apk`, executable `su` on PATH, common Magisk paths, `test-keys` build tag.
- **iOS indicators** — `/private/var/lib/cydia`, `/Applications/Cydia.app`, ability to fork(), writable `/private/`.
- **Plugins** — NCheck, ACTk (Anti-Cheat Toolkit) wrap the detection logic with regular updates.
- **Action** — gate online features (leaderboards, IAP, ranked) on rooted devices; warn the user; allow offline play.
- Don't outright ban — root users may be legitimate developers, accessibility tool users, or QA.

## Network protection

- **Certificate pinning** — pin the server's public key in client; reject MITM proxies (Charles, mitmproxy). Adds 1-2 days to an attacker's setup, not weeks. Ship a cert update path before you need it.
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
