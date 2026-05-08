---
name: unity-auth-account-linking
description: Use when wiring player identity, sign-in, and account linking in Unity through Unity MCP — authentication, auth, sign in, login, anonymous auth, anonymous user, Unity Authentication, Firebase Auth, Apple Sign In, Sign in with Apple, Google Sign In, Google Play Games sign in, Facebook Login, account linking, link account, unlink account, account merge, account recovery, password reset, OAuth, identity provider, IDP, JWT, token refresh, custom auth token, GUID, player GUID, player ID. NOT for save data (use unity-persistence + unity-cloud-save-conflict), NOT for IAP receipt user binding (use unity-iap). Unity 6 / 2023.2 LTS, URP-only, new Input System only.
---

## When to use

Any task that touches "who is this player" — anonymous bootstrap on first launch, "Sign in with Apple" buttons, linking an anonymous account to an identity provider, recovering a lost account, or refreshing auth tokens before calling protected backend endpoints. Cross-link `unity-cloud-save-conflict` (cloud save keyed to playerID), `unity-persistence` (token cache), `unity-iap` (entitlement binding), `unity-analytics-events` (user_id), `unity-crash-reporting` (user_id), `unity-best-practices`.

## Why anonymous-first

Forcing signup on first launch tanks D1 conversion roughly 30%. The anonymous-first pattern: device generates a UUID, service mints a `playerID`, player plays immediately with no friction. Linking to an identity provider (Apple, Google, Facebook) happens later — at strategic moments where the player has already invested (after first IAP, after first leaderboard win, after L5 completion, when toggling cloud sync in settings). Higher conversion than first-launch prompts and far higher than walls.

The cost: anonymous = device-bound. UUID lost (uninstall, factory reset, switch device, OS migration) = account lost. Critical to nudge linking before that loss happens.

## Pick a service

- **Unity Authentication (UGS)** — `com.unity.services.authentication`. Integrated with Unity Cloud Save / Cloud Code / Lobby / Relay. Anonymous + Apple + Google + Facebook + custom JWT (your own backend signing tokens). Best when the rest of the backend is UGS.
- **Firebase Authentication** — `FirebaseAuth.DefaultInstance`. Broader IDP set (Apple, Google, GitHub, Twitter/X, email-link, phone, custom JWT). Integrated with Crashlytics + Firebase Analytics. Best when the rest of the backend is Firebase (Firestore, Realtime DB, Cloud Functions).
- **PlayFab** — separate ecosystem. Common for studios already on PlayFab Title Data / Economy / CloudScript. Adds its own player IDs and inventory model; switching costs are high, so pick once.

Pick by where the rest of the backend lives. Mixing (e.g., Unity Auth + Firestore) works but you maintain two identity stores; not worth it for most indie projects.

## Anonymous auth

Device generates a UUID locally; SDK calls `SignInAnonymouslyAsync()`; service stores `(uuid -> playerID)`. Subsequent launches reuse the cached UUID and resume the same `playerID`.

```csharp
// Unity Authentication (UGS)
await UnityServices.InitializeAsync();
if (!AuthenticationService.Instance.IsSignedIn) {
    await AuthenticationService.Instance.SignInAnonymouslyAsync();
}
string playerID = AuthenticationService.Instance.PlayerId;
```

```csharp
// Firebase
var auth = FirebaseAuth.DefaultInstance;
if (auth.CurrentUser == null) {
    var result = await auth.SignInAnonymouslyAsync();
    string uid = result.User.UserId;
}
```

Anonymous UUID lives in app-private storage. PlayerPrefs is fine for the refresh-token cache (device-scoped, replaceable, low value to attackers); the anonymous identity itself is non-recoverable, so do not pretend it's a real account.

## Linking to identity providers

Pattern in every SDK: user taps "Link Apple" -> identity provider returns a signed identity token -> SDK calls `LinkWithCredential(token)` -> server upgrades anonymous record to linked. The anonymous `playerID` survives; only the auth method changes.

- **Apple Sign-In** — REQUIRED on iOS if you offer ANY 3rd-party login (App Store guideline 4.8). Returns Apple-signed identity token; server verifies via Apple JWKS. Use `com.lupidan.apple-signin-unity` or Unity's UGS Apple package. Needs Service ID + Team ID + Key ID + Private Key (.p8) configured on Apple Developer.
- **Google Sign-In** — Android + cross-platform. Returns Google ID token; server verifies via Google's public keys (`https://www.googleapis.com/oauth2/v3/certs`). Cross-platform variant uses `googlesignin-unity`; needs OAuth client ID per platform.
- **Google Play Games** — Android-specific; auto-detects existing Play account, smoother UX than generic Google Sign-In on Android. Use the GPGS plugin v2; sign-in returns a server auth code that your backend exchanges for an ID token.
- **Facebook Login** — legacy but still widely used. Facebook SDK -> access token -> exchange server-side. ATT prompt required on iOS before SDK fires (cross-link `unity-consent-att-gdpr`).

```csharp
// Unity Auth — link Apple to current anonymous user
await AuthenticationService.Instance.LinkWithAppleAsync(appleIdToken);
```

```csharp
// Firebase — link Apple credential
var credential = OAuthProvider.GetCredential("apple.com", appleIdToken, rawNonce, null);
await auth.CurrentUser.LinkWithCredentialAsync(credential);
```

## Cross-device handoff

The whole point of linking. Flow:

1. User installs on Phone A — anonymous bootstrap, plays, links Apple ID at L5.
2. User installs on Phone B — sees "Sign in with Apple" -> Apple returns identity token -> server matches existing Apple-linked `playerID` -> returns it.
3. Phone B has a fresh anonymous account from its install (`playerID_B`) and now wants to switch to the linked one (`playerID_A`).
4. App prompts: "We found cloud progress for this Apple ID. Use cloud progress / Keep this device's progress / Cancel."
5. Resolution = a save merge, which lives in `unity-cloud-save-conflict`. Identity layer's job ends at returning the canonical `playerID`.

## Token lifecycle

Auth tokens (JWTs) expire — Apple ~1h, Google ~1h, Firebase 1h, Unity Auth 1h. SDK auto-refreshes on each call. On refresh failure (revoked, password changed, account deleted), sign user out and route to re-auth flow.

Cache the refresh token (or session token, depending on SDK) so cold starts skip the IDP roundtrip. PlayerPrefs is acceptable for refresh tokens; they are device-scoped and replaceable. Don't cache the short-lived access token longer than its lifetime.

```csharp
// Unity Auth — token expiry callback
AuthenticationService.Instance.Expired += async () => {
    try { await AuthenticationService.Instance.SignInAnonymouslyAsync(); }
    catch { /* sign out, prompt re-auth */ }
};
```

## Account recovery

- Anonymous lost = lost. No recovery without prior linking. State this loudly in UI when offering link CTAs ("Never lose your progress").
- Linked user lost device = sign in via the same identity provider on the new device. The `playerID` is recovered via the IDP -> server lookup.
- Customer support flow when a user can't sign in: collect (in-game player ID, last-known device, identity provider used, approximate signup date) -> manually re-link via admin tools (UGS dashboard, Firebase console, or your own admin panel). Build the admin tool early; CS volume scales with linked-account problems.
- GDPR account deletion: must propagate through the identity provider chain. Deleting on your server alone leaves the IDP record dangling. Apple Sign-In specifically requires `app-store-connect` revoke endpoint calls.

## Common patterns

- "Sign in" prompt at strategic moments: after first IAP, after first leaderboard submit, after L5, when enabling cloud sync. Avoid first-launch unless your game is genuinely social (e.g., real-time multiplayer).
- "Link account" CTA in settings + a friendly explainer ("Never lose your progress"). Keep one-tap; do not ask for an email field on top.
- Multi-IDP linking — anonymous -> Apple link, then Apple -> Google ALSO link. Edge case but real for cross-platform players (iPhone + Android tablet). Both SDKs support it; UI should expose linked providers as a list with link/unlink buttons.
- Sign-out UX: warn that signing out of an anonymous account = data loss; for linked accounts, just confirm.

## Gotchas

- Apple Sign-In requires Service ID + Private Key (.p8) on Apple Developer. The Service ID has to match the bundle ID exactly; the .p8 expires never but you can only download it once at creation. Fiddly.
- Google Sign-In requires SHA1/SHA256 fingerprint matching the keystore. CI builds with separate keystores need separate OAuth client IDs in Google Cloud Console. Production keystore SHA1 is in Play Console > App signing.
- Anonymous -> Apple link conflict — user already has an Apple-linked account elsewhere. SDK throws `AuthenticationErrorCode.AccountAlreadyLinked` (or equivalent). Prompt: "This Apple ID is already used by another account. Switch to that account / cancel and stay anonymous."
- Linking sends current local `playerID` -> server. Server merges progress to canonical account. Conflict resolution is `unity-cloud-save-conflict`'s job; do not silently overwrite.
- Sign in with Apple required on iOS if any other 3rd-party login is offered. App Review will reject builds that ship Google/Facebook/etc on iOS without Apple as an option.
- TestFlight test accounts differ from production Apple IDs; sandbox vs prod confusion is common. Same for Google Play internal-testing accounts.
- Don't store identity provider tokens in plaintext PlayerPrefs on devices where the cache might be backed up (iCloud backup of iOS app data, Android auto-backup). Disable backup for the auth folder or encrypt at rest.
- Race on rapid double-tap of link button = duplicate link calls. Disable the button on tap; re-enable on completion or error.

## Verification

- First launch on fresh install: anonymous auth completes, `playerID` is non-empty, persisted across cold start.
- Tap "Link Apple" with a fresh Apple ID: server logs anonymous-to-Apple upgrade; `playerID` unchanged.
- Sign out + sign in with the same Apple ID on a different device: server returns the same `playerID`.
- Force token expiry (wait 1h or revoke server-side): SDK refreshes silently on next call; logs show refresh success.
- Auth-required backend endpoint (e.g., cloud save read) fails with 401 when token is missing, succeeds with valid token.
- Account deletion: server clears player data, IDP unlink endpoint called (Apple revoke, Google revoke), subsequent sign-in creates a new `playerID`.
- Multi-IDP: link Apple, then link Google to the same account, sign out, sign in via Google -> same `playerID`.
