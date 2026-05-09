---
name: unity-iap
description: 'Use when adding or operating in-app purchases in a Unity 6+ project through Unity MCP — Unity IAP v5, com.unity.purchasing, StoreController, CatalogProvider, ProductDefinition, PendingOrder, ConfirmPurchase, FetchProducts, FetchPurchases, CheckEntitlement, receipt validation, App Store Server API, Google Play Developer API, sandbox testing, refund webhooks. NOT for ad mediation (use unity-ads-mediation), NOT for player accounts (use unity-auth-account-linking). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Any task that wires real money to entitlements: shop UI, restore button, subscription status, sandbox tester setup, server receipt validation, refund webhook handling, deferred / Ask-to-Buy flows. iOS App Store + Google Play are required surfaces; desktop stores (Steam / Epic / Microsoft) usually use their own SDKs rather than Unity IAP.

Read `unity-best-practices` first. Cross-link `unity-persistence` (entitlement cache), `unity-build` (signed builds + Capabilities flag), `unity-analytics-events` (purchase telemetry), `unity-anti-cheat-iap-fraud` (server validation patterns).

## Unity 6+ fast path

Unity 6+ projects should use **Unity IAP v5** as the primary path. IAP v5 splits the old monolithic initialization flow into explicit store connection, product fetching, purchase fetching, and event-driven order handling.

Sequence:

1. Add `com.unity.purchasing` via the package manager.
2. Enable iOS **In-App Purchase** capability and Android billing setup through Player Settings / generated Gradle metadata.
3. Author a small shop service built around `StoreController`.
4. Editor console clean after import and code generation.
5. Verify only on real store test tracks: TestFlight / Xcode device for iOS, Play Internal Testing or Internal App Sharing for Android.

## Products

Define products in code for testability, or mirror an external product catalog into code at boot. Use one canonical Unity ID per product and map store-specific IDs server-side or in a small product registry.

`ProductType`:

- `Consumable` — coins, gems, energy. Buyable repeatedly.
- `NonConsumable` — remove ads, premium tier, expansion pack. Buyable once per account; restores must return them on reinstall.
- `Subscription` — battle pass, monthly pro. Renewal/refund/grace state must come from the store/server, not from a local bool.

Example product definitions:

```csharp
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Purchasing;

public static class IapProducts
{
    public const string Coins100 = "coins_100";
    public const string RemoveAds = "remove_ads";
    public const string ProMonthly = "pro_monthly";

    public static readonly List<ProductDefinition> Definitions = new()
    {
        new ProductDefinition(Coins100, ProductType.Consumable),
        new ProductDefinition(RemoveAds, ProductType.NonConsumable),
        new ProductDefinition(ProMonthly, ProductType.Subscription),
    };
}
```

Store-side IDs still need to exist in App Store Connect and Play Console before real purchases work. A missing or mismatched SKU usually appears as a product-fetch failure, not as a compile error.

## Initialization

Attach event handlers before connecting or fetching, then connect, fetch products, and fetch purchases. Treat each step as independently fallible; a good shop UI can show prices/products when available and a clear "store unavailable" state when not.

```csharp
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Purchasing;

public sealed class IapShopService : MonoBehaviour
{
    StoreController _store;
    readonly Dictionary<string, Product> _products = new();

    async void Awake()
    {
        await InitializeAsync();
    }

    async Task InitializeAsync()
    {
        _store = UnityIAPServices.StoreController();

        _store.OnProductsFetched += OnProductsFetched;
        _store.OnProductsFetchFailed += failure =>
            Debug.LogWarning($"IAP product fetch failed: {failure.FailureReason}");
        _store.OnPurchasesFetched += orders =>
            Debug.Log($"IAP purchases fetched: {orders}");
        _store.OnPurchasesFetchFailed += failure =>
            Debug.LogWarning($"IAP purchase fetch failed: {failure.FailureReason}");
        _store.OnPurchasePending += OnPurchasePending;
        _store.OnPurchaseFailed += failed =>
            Debug.LogWarning($"IAP purchase failed: {failed.Info.ProductId}");

        await _store.Connect();
        _store.FetchProducts(IapProducts.Definitions);
    }

    void OnProductsFetched(List<Product> products)
    {
        _products.Clear();
        foreach (var product in products)
            _products[product.definition.id] = product;

        _store.FetchPurchases();
    }

    public void Buy(string productId)
    {
        if (_products.TryGetValue(productId, out var product))
            _store.Purchase(product);
        else
            Debug.LogWarning($"IAP product not fetched: {productId}");
    }

    void OnPurchasePending(PendingOrder order)
    {
        StartCoroutine(SendOrderToServer(order));
    }

    System.Collections.IEnumerator SendOrderToServer(PendingOrder order)
    {
        // POST order.Info.Receipt / order.Info.Apple.jwsRepresentation plus product ID.
        // Wait for the backend to validate with Apple or Google and write entitlement.
        yield return null;

        _store.ConfirmPurchase(order);
    }
}
```

The sample is intentionally a thin service, not a full shop UI. Add UI binding in `unity-ugui` and analytics in `unity-analytics-events`.

## Purchase flow

End-to-end:

1. Client calls `StoreController.Purchase(product)`.
2. Store returns a `PendingOrder`.
3. Client posts trusted receipt/order data to backend.
4. Backend validates with Apple or Google.
5. Backend writes entitlement using a store-trusted transaction key.
6. Client syncs entitlement from backend.
7. Client calls `StoreController.ConfirmPurchase(order)`.

Grant consumables, subscriptions, and competitive entitlements only after the backend has written the entitlement row. For tiny offline-only games, client-side validation can be a conscious risk tradeoff, but document that it is not fraud-resistant.

## Receipt validation

**Server-side is the production source of truth.**

- **Apple — App Store Server API (primary).** Use signed transaction data / JWS. Avoid legacy receipt flows for new Unity 6+ work. Verify signatures and read subscription/refund/grace state from Apple's server APIs and notifications.
- **Google — Android Publisher API.** Service-account auth with scope `androidpublisher`. Validate products and subscriptions through the Play Developer API. Acknowledge purchases within the required window or Google refunds them.

Use the receipt/order fields exposed by IAP v5 (`Order.Info.Receipt`, Apple JWS fields where present) instead of older product-receipt flows. Full implementation cookbook with JWT generation, x5c chain verification, and Pub/Sub setup: see `references/server-validation.md`.

### Idempotency

Every grant operation MUST be keyed by a server-trusted transaction identifier — never by a client-supplied userId or request ID.

- **Apple** key = original transaction ID for subscription ownership, transaction ID for individual renewal events.
- **Google** key = purchase token.
- Server stores granted transaction IDs in a unique-indexed table. A second arrival returns the existing entitlement and is a no-op.
- Critical for client retries, duplicate webhook deliveries, and cross-device races.

### Cross-device race

Same Apple ID buys on two devices simultaneously, or an anonymous player links accounts while a purchase is pending.

- Server dedupes by store transaction key, not by client-supplied userId.
- Anonymous to linked transitions: migrate entitlements by canonical playerID server-side. Cross-link `unity-auth-account-linking`.

## Restore and entitlements

In IAP v5, confirmed purchases can be restored by fetching purchases or checking entitlement. Provide a visible Restore button for iOS apps that sell NonConsumables or Subscriptions; App Store Review expects it.

```csharp
public void RestorePurchases()
{
    _store.FetchPurchases();
}

public void CheckRemoveAds()
{
    if (_products.TryGetValue(IapProducts.RemoveAds, out var product))
        _store.CheckEntitlement(product);
}
```

On Google, owned NonConsumables and active Subscriptions are usually returned through purchase fetch/entitlement checks. Keep the Restore UI anyway for user trust and cross-platform consistency.

## Subscriptions

Treat local subscription state as advisory. Auto-renew, billing retry, grace periods, refunds, upgrades, and downgrades all flow through store APIs and webhooks.

Canonical state:

- **Apple**: App Store Server API subscription status endpoints and App Store Server Notifications V2.
- **Google**: `purchases.subscriptionsv2.get` and Real-time Developer Notifications.

Client responsibilities:

- show localized price and introductory offer text from fetched product metadata,
- initiate purchase,
- show pending/processing UX,
- sync entitlement state from the backend on boot and foreground.

## Sandbox testing

**iOS** — App Store Connect > Users and Access > Sandbox > Testers. Create a tester with an email not tied to a real Apple ID. On device, sign out of the App Store under Settings (not iCloud). Build to device via Xcode or TestFlight; trigger a purchase; enter sandbox tester credentials. Editor purchases never prove App Store behavior.

**Android** — Google Play Console > Setup > License Testing, add tester Gmail accounts. Upload a build to Internal Testing or use Internal App Sharing and opt the tester account into the track. Static response IDs can test UI paths but do not exercise real receipt flows.

Always test: first purchase, restore on fresh install, network drop mid-purchase, app kill mid-purchase, refund, subscription auto-renew, and entitlement sync on app foreground.

## Refunds and deferred purchases

**Refunds** — silent by default. Apple and Google notify your server, not the client. Without a webhook, a refunded user keeps the entitlement forever.

- **Apple — App Store Server Notifications V2.** JWS-signed webhook payload. Verify the certificate chain to Apple's root CA and trust only valid payloads.
- **Google — Real-time Developer Notifications.** Pub/Sub topic in your GCP project; dedupe at-least-once deliveries by message ID and store purchase token.

Full webhook verification recipe: see `references/server-validation.md`.

**Deferred / Ask to Buy** — purchase may complete hours or days later. The pending-order handler can fire on a later launch. Never grant from the button click itself; grant only after store/server validation.

## Promotional / introductory pricing

**iOS** — App Store Connect authors introductory offers, promotional offers, and offer codes. In IAP v5, prefer the Apple extended store service APIs exposed by the package version in the project. Reflect on the installed package if docs and local API names diverge.

**Google** — subscription offers configured in Play Console; query product/offer details from fetched product metadata and let Google enforce eligibility.

## Common patterns

- **Shop boot** — connect to store, fetch products, populate UI from fetched metadata, then fetch purchases/entitlements.
- **Buy button** — disable until products are fetched and while an order is pending.
- **Entitlement sync** — fetch from backend on boot and `OnApplicationFocus(true)` to catch refunds, deferred completions, and cross-device purchases.
- **Catalog change** — adding a SKU requires store-console entries plus a product definition in code; mismatches become product-fetch failures.

## Gotchas

- Editor store behavior is fake. Test real iOS/Android flows on real devices and store tracks.
- Do not trust client-only receipts for currency, competitive unlocks, or anything transferable.
- Use store transaction IDs / purchase tokens for idempotency. Do not key grants by UI button press or local save state.
- Forgetting to confirm a validated pending order causes repeat delivery and a stuck transaction.
- Google purchase acknowledgement is time-limited; make validation and confirmation part of the launch checklist.
- Bundle ID mismatch between dev/prod builds makes store validation reject otherwise valid transactions.
- Package docs and local package APIs can drift; reflect on the installed `com.unity.purchasing` assembly before writing platform-specific extended-service calls.

## Legacy migration notes

Older Unity IAP implementations used listener/controller initialization, product builders, and product-level purchase callbacks. Do not copy those examples into Unity 6+ work. When migrating, translate the old flow into:

- connect store,
- fetch products,
- fetch purchases,
- handle pending orders,
- validate on backend,
- confirm the pending order,
- fetch/check entitlements for restore.

Keep the old implementation compiling only long enough to migrate one product path at a time.

## Verification

- Editor console is clean after package install and shop-service compile.
- Product fetch returns every SKU expected for the active store track.
- Sandbox purchase succeeds end-to-end on a real iOS device and real Android device.
- Server validation roundtrip succeeds; entitlement row is written; client confirms the pending order.
- Fresh install + restore/fetch retrieves all NonConsumables and active Subscriptions.
- Forced sandbox refund triggers webhook; entitlement is revoked; client picks up revocation on next foreground sync.
- Subscription auto-renew in sandbox updates server state without a new button press.
- `LogAssert` is clean across init, purchase, restore, refund, and app-kill-during-purchase paths.
