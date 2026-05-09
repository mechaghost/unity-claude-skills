---
name: unity-auth-account-linking
description: 'Use for Unity player identity: anonymous auth, Unity/Firebase Auth, Apple/Google/Facebook/GPGS sign-in, account linking/unlinking, recovery, OAuth/JWT tokens, refresh storage, player IDs. Not save data or IAP receipt binding. Unity 6+ / URP / new Input System.'
---

## When to use

Use for "who is this player": anonymous bootstrap, Sign in with Apple/Google/Facebook, linking, recovery, and token refresh. Cross-links: `unity-cloud-save-conflict`, `unity-persistence`, `unity-iap`, `unity-analytics-events`, `unity-crash-reporting`.

## Why anonymous-first

Anonymous-first: device/session gets a service `playerID`, player starts immediately, linking happens later at a high-intent moment (first IAP, leaderboard, level milestone, cloud-sync toggle). Avoid first-launch walls unless the game is inherently social.

Cost: anonymous accounts are device-bound. Uninstall/factory reset/device switch can lose them, so nudge linking before risk points.

## Pick a service

- **Unity Authentication (UGS)** — best with Unity Cloud Save / Cloud Code / Lobby / Relay.
- **Firebase Auth** — best with Firestore/Realtime DB/Cloud Functions/Crashlytics/Firebase Analytics; broad IDP support.
- **PlayFab** — good if already using PlayFab Title Data/Economy/CloudScript; switching costs are high.

Pick where the backend already lives. Mixing identity stores is rarely worth it.

## Anonymous auth

Device/session signs in anonymously; service returns stable `playerID`. Subsequent launches resume it from SDK/session cache.

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

Anonymous identity is non-recoverable. Store only low-value anonymous bootstrap state locally; do not present it as a durable account.

## Linking to identity providers

Common pattern: tap "Link Apple/Google" -> IDP returns signed token -> SDK/backend links credential -> anonymous `playerID` survives, auth method changes.

- **Apple Sign-In** — required on iOS if any third-party login exists. Verify Apple JWT via JWKS. Needs Service ID, Team ID, Key ID, and `.p8`.

  Nonce replay defense: client creates random raw nonce, sends `SHA256(nonce)` to Apple, sends raw nonce + token to backend, backend verifies JWT `nonce == SHA256(raw_nonce)` and rejects missing/mismatched/reused nonces.

  Server checks: JWKS signature by `kid`, `iss == https://appleid.apple.com`, correct `aud`, valid `exp/iat`, valid nonce. Cache JWKS per `Cache-Control`; refetch on missing `kid`.

- **Google Sign-In** — verify ID token via Google's certs; check signature, `iss`, `aud`, and `exp`. Prefer maintained libraries (`google-auth-library`, `verify_oauth2_token`, `GoogleIdTokenVerifier`) over hand-rolled JWT parsing.
- **Google Play Games** — Android-specific; GPGS v2 returns a server auth code for backend exchange.
- **Facebook Login** — SDK access token -> server exchange. On iOS, ATT must precede SDK tracking (`unity-consent-att-gdpr`).

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

Linking enables device handoff:

1. User installs on Phone A — anonymous bootstrap, plays, links Apple ID at L5.
2. User installs on Phone B — sees "Sign in with Apple" -> Apple returns identity token -> server matches existing Apple-linked `playerID` -> returns it.
3. Phone B may have a fresh anonymous `playerID_B`; server now knows linked `playerID_A`.
4. Prompt: "We found cloud progress. Use cloud / Keep device / Cancel."
5. Save merge belongs to `unity-cloud-save-conflict`; identity returns canonical `playerID`.

## Token lifecycle

JWTs expire (~1h typical). SDKs usually refresh on calls. Refresh failure (revoked/password changed/deleted) -> sign out and re-auth.

Cache refresh/session tokens for cold start, but not in PlayerPrefs. Refresh tokens resume sessions and need secure storage:

- **iOS** — Keychain, preferably `ThisDeviceOnly`.
- **Android** — `EncryptedSharedPreferences` backed by Android Keystore.
- **Access tokens** — keep in memory; refresh token mints a new one after cold start.

Anonymous bootstrap state is lower value; still disable cloud/auto-backup for auth cache folders.

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
- Support recovery: collect player ID, last device, IDP, approximate signup date; re-link through admin tooling.
- GDPR deletion must propagate through backend and IDP unlink/revoke endpoints (Apple requires revoke).

## Common patterns

- Prompt after value moments: first IAP, leaderboard, L5, enabling cloud sync.
- Settings CTA: "Link account" / "Never lose progress"; keep it one-tap.
- Multi-IDP linking is real for cross-platform players; show linked providers with link/unlink buttons.
- Sign-out UX: warn that signing out of an anonymous account = data loss; for linked accounts, just confirm.

## Gotchas

- Apple `.p8` is downloadable only once; store it securely.
- Google Sign-In needs SHA1/SHA256 fingerprints matching each keystore; CI/release keystores need separate OAuth clients.
- Anonymous -> Apple link conflict — user already has an Apple-linked account elsewhere. SDK throws `AuthenticationErrorCode.AccountAlreadyLinked` (or equivalent). Prompt: "This Apple ID is already used by another account. Switch to that account / cancel and stay anonymous."
- Linking sends current local `playerID` -> server. Server merges progress to canonical account. Conflict resolution is `unity-cloud-save-conflict`'s job; do not silently overwrite.
- Sign in with Apple required on iOS if any other 3rd-party login is offered. App Review will reject builds that ship Google/Facebook/etc on iOS without Apple as an option.
- TestFlight / Play internal-testing accounts differ from production; verify both sandbox and prod flows.
- Never store IDP tokens in plaintext PlayerPrefs; disable backup for auth cache or encrypt.
- Race on rapid double-tap of link button = duplicate link calls. Disable the button on tap; re-enable on completion or error.

## Verification

- First launch on fresh install: anonymous auth completes, `playerID` is non-empty, persisted across cold start.
- Tap "Link Apple" with a fresh Apple ID: server logs anonymous-to-Apple upgrade; `playerID` unchanged.
- Sign out + sign in with the same Apple ID on a different device: server returns the same `playerID`.
- Force token expiry (wait 1h or revoke server-side): SDK refreshes silently on next call; logs show refresh success.
- Auth-required backend endpoint (e.g., cloud save read) fails with 401 when token is missing, succeeds with valid token.
- Account deletion: server clears player data, IDP unlink endpoint called (Apple revoke, Google revoke), subsequent sign-in creates a new `playerID`.
- Multi-IDP: link Apple, then link Google to the same account, sign out, sign in via Google -> same `playerID`.
