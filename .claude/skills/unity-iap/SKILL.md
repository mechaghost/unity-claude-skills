---
name: unity-iap
description: Use when adding or operating in-app purchases in a Unity project through Unity MCP — IAP, in-app purchase, Unity IAP, com.unity.purchasing, ProductCatalog, IStoreController, IExtensionProvider, ConfigurationBuilder, AddProduct, ProductType, Consumable, NonConsumable, Subscription, InitiatePurchase, ProcessPurchaseResult, RestoreTransactions, receipt validation, App Store receipt, Google Play receipt, sandbox testing, IAP test account, refund, deferred purchase, Ask to Buy, store-specific extensions, App Store Connect IAP, Google Play Console IAP, AppleAppStore, GooglePlay, ConfirmSubscriptionPriceChange, ProductMetadata, Apple receipt validation, Google receipt validation, server-side receipt verification, GameAnalytics IAP, IAP fraud, receipt forgery. NOT for ad mediation (use unity-ads-mediation), NOT for player accounts (use unity-auth-account-linking). Unity 6 / 2023.2 LTS, URP-only, new Input System only.
---

## When to use

Any task that wires real money to entitlements: shop UI, restore button, subscription status, sandbox tester setup, server receipt validation, refund webhook handling, deferred / Ask-to-Buy flows. iOS App Store + Google Play are required surfaces; desktop stores (Steam / Epic / Microsoft) are mentioned but each has its own SDK — Unity IAP routes through `WindowsStore`/`MacAppStore` only, which most indie desktop releases skip in favor of native Steamworks.

Read `unity-best-practices` first. Cross-link `unity-persistence` (entitlement save), `unity-build` (signed builds + Capabilities flag), `unity-analytics-events` (purchase telemetry), `unity-anti-cheat-iap-fraud` (server validation patterns).

## Package install

Install `com.unity.purchasing` via Package Manager (Window > Package Manager > Unity Registry > In App Purchasing). Unity 6's recommended path is the 4.x line; on iOS 17+ enable the StoreKit 2 backend in `Window > Unity IAP > IAP Settings`. Enable the **In-App Purchase** Capability in Player Settings (iOS) and add the `com.android.vending.BILLING` permission (auto-added by the package on Android).

## Catalog and product types

Open `Window > Unity IAP > IAP Catalog`. Define products with cross-store IDs — App Store conventionally uses dotted reverse-DNS (`com.studio.game.coins100`), Google Play uses lowercase + underscores (`com_studio_game_coins100`). The catalog stores both per-store IDs and a canonical Unity ID so your client code references one string.

`ProductType`:
- `Consumable` — coins, gems, energy. Buyable repeatedly. Apple finishes immediately on consume; Google requires `consumeAsync`.
- `NonConsumable` — remove ads, premium tier, expansion pack. Buyable once per account; restores must return them on reinstall.
- `Subscription` — battle pass, monthly pro. Auto-renewing receipts arrive unprompted; status read via `SubscriptionManager`.

Export the catalog (`Automatically initialize UnityPurchasing` checkbox) or build `ConfigurationBuilder` in code; code-driven is more testable.

## Initialization

```csharp
public sealed class IapBoot : MonoBehaviour, IDetailedStoreListener {
    IStoreController _controller;
    IExtensionProvider _extensions;

    void Start() {
        var builder = ConfigurationBuilder.Instance(StandardPurchasingModule.Instance());
        builder.AddProduct("coins_100", ProductType.Consumable, new IDs {
            { "com.studio.game.coins100", AppleAppStore.Name },
            { "com_studio_game_coins100", GooglePlay.Name },
        });
        builder.AddProduct("remove_ads", ProductType.NonConsumable, new IDs { /* ... */ });
        builder.AddProduct("pro_monthly", ProductType.Subscription, new IDs { /* ... */ });
        UnityPurchasing.Initialize(this, builder);
    }

    public void OnInitialized(IStoreController c, IExtensionProvider e) { _controller = c; _extensions = e; }
    public void OnInitializeFailed(InitializationFailureReason r, string msg) { /* retry w/ backoff */ }
    public PurchaseProcessingResult ProcessPurchase(PurchaseEventArgs e) { /* see below */ }
    public void OnPurchaseFailed(Product p, PurchaseFailureDescription d) { /* log + UX */ }
}
```

`OnInitialized` is the only place to capture `IExtensionProvider`. Stash it on a singleton — `RestoreTransactions` and Apple-specific calls need it.

Init can fail (no internet, store down, missing capability). Implement bounded retry and a "store unavailable" UX path; never block the main menu on it.

## Purchase flow

```csharp
public void Buy(string productId) {
    var p = _controller.products.WithID(productId);
    if (p != null && p.availableToPurchase) _controller.InitiatePurchase(p);
}

public PurchaseProcessingResult ProcessPurchase(PurchaseEventArgs e) {
    // 1. Verify productID matches what we expect for this transaction context.
    // 2. Send e.purchasedProduct.receipt to server for validation.
    // 3. If we will grant on server confirmation -> return Pending.
    // 4. If we already granted (offline/local-only product) -> return Complete.
    StartCoroutine(ValidateOnServer(e.purchasedProduct));
    return PurchaseProcessingResult.Pending; // server flow
}
```

Return values:
- `Complete` — Unity IAP finishes the transaction with the store immediately.
- `Pending` — transaction stays open; you MUST call `_controller.ConfirmPendingPurchase(product)` once the server grants entitlement. If you forget, Unity IAP re-delivers the same receipt to `ProcessPurchase` on every launch.

## Receipt validation (client + server)

**Client-side (`CrossPlatformValidator`)** — bundles certificates via Tangle files generated by `Window > Unity IAP > Receipt Validation Obfuscator`. Catches casual tampering and the "edit JSON in transit" crowd; does NOT stop a determined attacker who can patch the binary or replace tangle files. Useful as a first gate, never as the only gate.

Tangle files are derived from public store certificates and ship inside the binary — they are not secrets, but they MUST be rotated when leaked or when the upstream cert rotates. Never put your App Store **shared secret** on the client; it stays server-side and is only used by the legacy `verifyReceipt` path. App Store Server API uses your .p8 private key (server-only, never shipped). See `unity-anti-cheat-iap-fraud` for tampering-detection patterns.

```csharp
var validator = new CrossPlatformValidator(
    GooglePlayTangle.Data(), AppleTangle.Data(), Application.identifier);
try {
    var receipts = validator.Validate(args.purchasedProduct.receipt);
    foreach (var r in receipts) Debug.Log($"valid: {r.productID}");
} catch (IAPSecurityException) { /* reject */ }
```

**Server-side (required for any real revenue)**:

- **Apple — App Store Server API (primary)**. Endpoints: production `https://api.storekit.itunes.apple.com`, sandbox `https://api.storekit-stage.itunes.apple.com`. The notification's `environment` field (or which store the client transacted against) tells you which base URL to hit — there is no `21007` retry dance. Call `GET /inApps/v1/transactions/{transactionId}` to fetch a signed JWS-encoded transaction. Verify `bundleId`, `productId`, transaction uniqueness (store `originalTransactionId`). For subscription state use `GET /inApps/v1/subscriptions/{originalTransactionId}` (Get All Subscription Statuses).
- **Apple — `verifyReceipt` (legacy)**. Deprecated by Apple; only useful for legacy receipts emitted before App Store Server API rollout. Do not build new integrations on it.
- **Apple JWS auth (ES256)** — App Store Server API requires a short-lived ES256 JWT in the `Authorization` header.
  - Generate the token with max 20-minute lifetime; rotate aggressively.
  - Header: `{ "alg": "ES256", "kid": "<your key ID>", "typ": "JWT" }`
  - Payload: `{ "iss": "<your issuer ID>", "iat": <unix>, "exp": <unix+1200>, "aud": "appstoreconnect-v1", "bid": "<your bundle ID>" }`
  - Sign with the .p8 private key downloaded once from App Store Connect (Users and Access > Keys > In-App Purchase). Issuer ID and Key ID are on that same page.
  - Send as `Authorization: Bearer <jwt>` on every request. Cache the JWT for its lifetime; do not regenerate per-call.
- **Google — Android Publisher API**. Full REST paths:
  - Products: `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{token}`
  - Subscriptions V2: `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}`
  Use a service account with the Android Publisher API enabled (`purchases.products.get` / `purchases.subscriptionsv2.get` are the SDK shorthand for these paths). Acknowledge within 3 days or Google auto-refunds.

End-to-end: client `InitiatePurchase` -> `ProcessPurchase` returns `Pending` -> POST `{receipt, productId, userId}` to your backend -> backend validates with the store -> backend writes entitlement to your DB -> client polls or listens (push / next entitlement sync) -> `ConfirmPendingPurchase`. Grant the in-game item only after the entitlement row exists server-side.

### Idempotency

Every grant operation MUST be keyed by a server-trusted transaction identifier — never by a client-supplied userId or request ID.

- **Apple** key = `originalTransactionId` (covers the original purchase + every auto-renewal that shares it; pair with `transactionId` when distinguishing renewals).
- **Google** key = `purchaseToken`.
- Server stores granted txIDs in a unique-indexed table. Second arrival of the same txID returns the existing entitlement row and is a no-op — never grants twice.
- Critical for client retries (`ProcessPurchase` re-fires until `ConfirmPendingPurchase`), duplicate webhook deliveries, and cross-device races.

### Cross-device race

Same Apple ID buys on two devices simultaneously (or anonymous-then-linked transitions): both clients post receipts within seconds of each other.

- Server dedupes by `originalTransactionId` (Apple) / `purchaseToken` (Google), NOT by client-supplied userId. The first arrival wins; the second hits the unique index and returns the existing entitlement.
- Anonymous to linked transitions: when the client links an anonymous account to an IDP-backed playerID, migrate entitlements by canonical playerID server-side. Cross-link `unity-auth-account-linking` for the linking flow.

## Restore

```csharp
public void Restore() {
    if (Application.platform == RuntimePlatform.IPhonePlayer) {
        _extensions.GetExtension<IAppleExtensions>().RestoreTransactions((ok, err) => {
            if (!ok) Debug.LogWarning($"restore failed: {err}");
        });
    } else {
        // Android: re-initialize, or call IGooglePlayStoreExtensions.RestoreTransactions in 4.x.
    }
}
```

App Store Review **rejects** apps that sell NonConsumables or Subscriptions without a visible Restore button. Place it in Settings; calling it triggers a sign-in prompt on iOS, so don't auto-fire it on launch.

On Google, `OnInitialized` already redelivers owned NonConsumables and active Subscriptions through `ProcessPurchase`, so the "restore" UI exists mostly to satisfy users coming from iOS muscle-memory.

## Subscriptions

`SubscriptionManager` parses receipts into `SubscriptionInfo` (active flag, expiry, free-trial state, auto-renew toggle, intro-price flag). Treat client values as advisory only — auto-renew, billing-retry, grace periods, and refunds all flow through server hooks. Source of truth = your server.

```csharp
// Unity IAP 4.x: 3-arg ctor (product, introJson, validator).
// IAP 3.x had a 2-arg ctor; that signature no longer compiles in 4.x.
var info = new SubscriptionManager(product, introJson, validator).getSubscriptionInfo();
bool active = info.isSubscribed() == Result.True;
bool freeTrial = info.isFreeTrial() == Result.True;
```

`SubscriptionManager` parses the local receipt only. For canonical state (renewal, billing retry, grace, refund), prefer the server APIs:
- **Google**: `purchases.subscriptionsv2.get` (REST: `/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}`).
- **Apple**: App Store Server API `Get All Subscription Statuses` (`GET /inApps/v1/subscriptions/{originalTransactionId}`).

## Sandbox testing

**iOS** — App Store Connect > Users and Access > Sandbox > Testers. Create a tester with an email NOT tied to a real Apple ID. On the device, sign **out** of the App Store under Settings (not iCloud). Build to device via Xcode or TestFlight; trigger a purchase; the StoreKit prompt asks for credentials — enter the sandbox tester. Editor purchases use the FakeStore; they never round-trip Apple, so always finish iOS validation on TestFlight.

**Android** — Google Play Console > Setup > License Testing, add tester Gmail accounts. Upload a build to an Internal Testing track (or use Internal App Sharing) and opt the tester's account into the test track. Static response IDs (`android.test.purchased`, `android.test.canceled`) work without Play Console at all but won't exercise real receipt flows.

Always test: first purchase, restore on fresh install, network drop mid-purchase, app kill mid-purchase, refund (force a refund from sandbox account), subscription auto-renew (Apple sandbox renews monthly subs every 5 min).

## Refunds and deferred purchases

**Refunds** — silent by default. Apple and Google notify your server, not the client. Without a webhook, a refunded user keeps the entitlement forever.
- **Apple — App Store Server Notifications V2**. HTTPS endpoint receives a JWS compact form payload (`header.payload.signature`). Verification is mandatory before trusting the body:
  - Decode the JWS header (base64url) and extract the `x5c` cert chain.
  - The leaf cert in `x5c` verifies the JWS signature.
  - Verify the cert chain ends at Apple's root CA (download from Apple's PKI page; pin the root and rotate annually).
  - Verify `alg = ES256` in the header. Reject anything else — never accept `none`, RS256, or unexpected algs.
  - Only after the chain validates do you parse and trust the payload (notification types: `REFUND`, `REVOKE`, `CONSUMPTION_REQUEST`, `DID_RENEW`, `EXPIRED`, `GRACE_PERIOD_EXPIRED`, ...).
- **Google — Real-time Developer Notifications**. Notifications arrive via a Pub/Sub topic in your GCP project. Setup:
  - Create the Pub/Sub topic in the same GCP project as the Play Console linked project.
  - Grant the role `roles/pubsub.publisher` to `google-play-developer-notifications@system.gserviceaccount.com` on that topic.
  - Subscribe to the topic via push (HTTPS endpoint with auth token) or pull from your backend.
  - In Play Console > Monetization setup, point the topic name at the topic you created.
  - Each Pub/Sub message includes attributes (`notificationType`, `purchaseToken`, ...) and a `messageId`. Dedupe by `messageId` — Pub/Sub guarantees at-least-once, not exactly-once.
  - For consumable refunds use the voided-purchases API in addition to RTDN.

On notification: revoke entitlement server-side. On client app boot, sync entitlements from server before unlocking gated content.

**Deferred / Ask to Buy** — child account requires parental approval; purchase enters Pending and may complete hours or days later (or be canceled). `ProcessPurchase` will fire whenever the resolution lands — possibly on a cold app launch. Never grant the item from button-press UX; only from `ProcessPurchase`. Show "purchase pending approval" UI and clear it when the receipt finalizes.

## Promotional / introductory pricing

**iOS** — App Store Connect lets you author Introductory Offers (auto-applied to first-time subscribers) and Promotional Offers (you generate signed JWT offer payloads server-side, pass to `IAppleExtensions.PresentOfferCodeRedeemptionSheet` or `PromotionalOffer.SignPromotionalOffer`). Offer codes redeemable via the App Store sheet are zero-config on the client.

**Google** — subscription offers configured in Play Console; query via `SubscriptionOfferDetails` on the product. Eligibility (e.g. "new subscribers only") is enforced by Google.

## Common patterns

- **Shop boot** — populate UI from `_controller.products` after `OnInitialized`; show localized price via `product.metadata.localizedPriceString` (never hardcode "$0.99").
- **Buy button** — disable while `availableToPurchase == false` or while any purchase is pending.
- **Entitlement sync** — fetch from server on app foreground (`OnApplicationFocus(true)`) to catch out-of-band refunds, deferred completions, and cross-device subscriptions.
- **Catalog change** — adding a SKU requires App Store Connect + Play Console entries plus a `ConfigurationBuilder.AddProduct` call; mismatches make the product silently `null` in `_controller.products`.

## Gotchas

- Editor uses the FakeStore — purchase always succeeds, receipt is bogus. Never validate iOS/Android flows in Editor; build to TestFlight / Internal Testing.
- Apple receipt lives at `Application.persistentDataPath` accessor `appStoreReceipt` (base64); for unified flows pass `e.purchasedProduct.receipt` (Unity-wrapped JSON containing `Payload`).
- Never trust a client-only receipt for hard goods, currency, or anything that affects other players. Server validation is mandatory.
- `PurchaseEventArgs.purchasedProduct.definition.id` is the Unity catalog ID, not the store ID — verify it matches the product the user tapped to defeat client-side spoofing of the SKU.
- Subscription auto-renewals fire `ProcessPurchase` with no user action. Idempotency key on transaction ID is required server-side or you'll double-grant.
- Forgetting `ConfirmPendingPurchase` after server grant means the receipt re-delivers on every launch — looks like a bug, is a missed call.
- Refund without server hooks = silent fraud loss. Treat hooks as P0 launch blockers, not "we'll add it later."
- Google requires acknowledgement within 3 days; Unity IAP acknowledges on `Complete` but NOT on `Pending` — your server flow must call the acknowledgement (or trigger client `ConfirmPendingPurchase`) before the deadline.
- `Application.identifier` mismatch (e.g. dev bundle ID `com.studio.game.dev`) makes Apple validation reject the receipt with `21010` / wrong-environment errors.

## Verification

- Sandbox purchase succeeds end-to-end on a real iOS device + a real Android device.
- `CrossPlatformValidator.Validate` returns receipts without throwing.
- Server validation roundtrip succeeds; entitlement row written; client confirms pending.
- Fresh install + restore retrieves all NonConsumables and active Subscriptions.
- Forced sandbox refund triggers webhook; entitlement revoked; client picks up revocation on next foreground sync.
- Subscription auto-renew (sandbox) fires `ProcessPurchase` on its own and server records the renewal.
- `LogAssert` is clean across init, purchase, restore, refund paths.
