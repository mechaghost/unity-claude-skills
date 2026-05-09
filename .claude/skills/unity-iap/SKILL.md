---
name: unity-iap
description: 'Use when adding or operating in-app purchases in a Unity 6+ project through Unity MCP — Unity IAP v5, com.unity.purchasing, StoreController, CatalogProvider, ProductDefinition, PendingOrder, ConfirmPurchase, FetchProducts, FetchPurchases, CheckEntitlement, receipt validation, App Store Server API, Google Play Developer API, sandbox testing, refund webhooks. NOT for ad mediation (use unity-ads-mediation), NOT for player accounts (use unity-auth-account-linking). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Wires real money to entitlements: shop UI, restore button, subscription status, sandbox tester setup, server receipt validation, refund webhooks, deferred / Ask-to-Buy. iOS App Store + Google Play required; desktop stores (Steam / Epic / Microsoft) use their own SDKs.

Read `unity-best-practices` first. Cross-link `unity-persistence` (entitlement cache), `unity-build` (signed builds + Capabilities), `unity-analytics-events` (purchase telemetry), `unity-anti-cheat-iap-fraud` (server validation patterns).

## Unity 6+ fast path

Use **Unity IAP v5**. Splits old monolithic init into explicit store connection, product fetch, purchase fetch, event-driven order handling.

1. Add `com.unity.purchasing` via package manager.
2. Enable iOS **In-App Purchase** capability + Android billing through Player Settings / Gradle.
3. Author shop service around `StoreController`.
4. Editor console clean after import.
5. Verify only on real store tracks: TestFlight / Xcode device (iOS), Play Internal Testing or Internal App Sharing (Android).

## Products

Define in code or mirror an external catalog at boot. One canonical Unity ID per product; map store IDs server-side or in a registry.

`ProductType`:

- `Consumable` — coins, gems, energy. Repeatable.
- `NonConsumable` — remove ads, premium tier, expansion. Once per account; restores must return on reinstall.
- `Subscription` — battle pass, monthly pro. Renewal/refund/grace from store/server, never a local bool.

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

Store-side IDs must exist in App Store Connect / Play Console. Missing or mismatched SKU = product-fetch failure, not compile error.

## Initialization

Attach handlers before connect/fetch. Each step is independently fallible — surface "store unavailable" cleanly.

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

Thin service only. UI binding in `unity-ugui`; analytics in `unity-analytics-events`.

## Purchase flow

1. Client calls `StoreController.Purchase(product)`.
2. Store returns `PendingOrder`.
3. Client posts trusted receipt/order to backend.
4. Backend validates with Apple or Google.
5. Backend writes entitlement keyed by store transaction.
6. Client syncs entitlement.
7. Client calls `StoreController.ConfirmPurchase(order)`.

Grant consumables, subscriptions, competitive entitlements only after backend writes the entitlement row. Tiny offline-only games can do client-side validation as a documented risk tradeoff — not fraud-resistant.

## Receipt validation

**Server-side is the source of truth.**

- **Apple — App Store Server API.** Use signed transaction data / JWS. Avoid legacy receipt flows. Read subscription/refund/grace from Apple's server APIs and notifications.
- **Google — Android Publisher API.** Service-account auth, scope `androidpublisher`. Acknowledge purchases within the required window or Google refunds them.

Use IAP v5 fields (`Order.Info.Receipt`, Apple JWS where present). Full cookbook (JWT, x5c chain, Pub/Sub): `references/server-validation.md`.

### Idempotency

Every grant MUST key by a server-trusted transaction ID — never client userId or request ID.

- **Apple** — original transaction ID for subscription ownership; transaction ID for individual renewals.
- **Google** — purchase token.
- Server stores granted IDs in unique-indexed table. Second arrival no-ops.
- Critical for client retries, duplicate webhooks, cross-device races.

### Cross-device race

Same Apple ID buys on two devices, or anonymous links accounts mid-purchase.

- Server dedupes by store transaction key, not client userId.
- Anonymous→linked: migrate entitlements by canonical playerID server-side. See `unity-auth-account-linking`.

## Restore and entitlements

In v5, fetch purchases or check entitlement. Provide a visible Restore button on iOS for NonConsumables / Subscriptions — App Store Review expects it.

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

On Google, owned NonConsumables and active Subscriptions return through purchase fetch. Keep the Restore UI for cross-platform consistency.

## Subscriptions

Local subscription state is advisory. Auto-renew, billing retry, grace, refunds, upgrades, downgrades flow through store APIs and webhooks.

Canonical state:

- **Apple** — App Store Server API status endpoints + Notifications V2.
- **Google** — `purchases.subscriptionsv2.get` + Real-time Developer Notifications.

Client:

- show localized price + intro offer text from product metadata,
- initiate purchase,
- show pending/processing UX,
- sync entitlement from backend on boot + foreground.

## Sandbox testing

**iOS** — App Store Connect > Users and Access > Sandbox > Testers. Tester email not tied to real Apple ID. On device, sign out of App Store under Settings (not iCloud). Build via Xcode/TestFlight; trigger purchase; enter sandbox creds. Editor purchases prove nothing.

**Android** — Play Console > Setup > License Testing, add tester Gmail accounts. Upload to Internal Testing or use Internal App Sharing; opt tester into the track. Static response IDs test UI paths only — no real receipts.

Always test: first purchase, restore on fresh install, network drop mid-purchase, app kill mid-purchase, refund, subscription auto-renew, entitlement sync on foreground.

## Refunds and deferred purchases

**Refunds** silent by default — Apple/Google notify your server, not the client. No webhook = refunded user keeps entitlement forever.

- **Apple — App Store Server Notifications V2.** JWS-signed; verify cert chain to Apple's root CA.
- **Google — Real-time Developer Notifications.** Pub/Sub topic in your GCP project; dedupe at-least-once deliveries by message ID.

Webhook recipe: `references/server-validation.md`.

**Deferred / Ask to Buy** — purchase may complete hours/days later. Pending-order handler can fire on a later launch. Never grant from button click; grant only after store/server validation.

## Promotional / introductory pricing

**iOS** — App Store Connect authors intro offers, promotional offers, offer codes. Prefer the Apple extended store service APIs in v5; reflect on the installed package if docs and local API names diverge.

**Google** — subscription offers in Play Console; query offer details from product metadata; let Google enforce eligibility.

## Common patterns

- **Shop boot** — connect, fetch products, populate UI, fetch purchases/entitlements.
- **Buy button** — disabled until products fetched and while order pending.
- **Entitlement sync** — fetch from backend on boot + `OnApplicationFocus(true)` (catches refunds, deferred completions, cross-device).
- **Catalog change** — new SKU = store-console entry + product definition; mismatches surface as fetch failures.

## Gotchas

- Editor store behavior is fake. Test real iOS/Android on real devices/tracks.
- Don't trust client-only receipts for currency, competitive unlocks, or transferable items.
- Use store transaction IDs / purchase tokens for idempotency. Never key by button press or local save.
- Forgetting to confirm a validated pending order = repeat delivery + stuck transaction.
- Google acknowledgement is time-limited (3 days) — make validation+confirmation part of the launch checklist.
- Bundle ID mismatch dev/prod = store validation rejects.
- Reflect on `com.unity.purchasing` before writing platform-specific extended-service calls — local APIs drift from docs.

## Legacy migration notes

Older IAP used listener/controller init, product builders, product-level callbacks. Don't copy into Unity 6+ work. Translate to:

- connect store,
- fetch products,
- fetch purchases,
- handle pending orders,
- validate on backend,
- confirm pending order,
- fetch/check entitlements for restore.

Keep old implementation compiling only long enough to migrate one product path at a time.

## Verification

- Editor console clean after package install + shop-service compile.
- Product fetch returns every SKU for active store track.
- Sandbox purchase succeeds end-to-end on real iOS + real Android.
- Server validation roundtrip succeeds; entitlement row written; client confirms pending order.
- Fresh install + restore retrieves all NonConsumables + active Subscriptions.
- Forced sandbox refund triggers webhook; entitlement revoked; client picks up on next foreground.
- Subscription auto-renew in sandbox updates server state without a new button press.
- `LogAssert` clean across init, purchase, restore, refund, app-kill-during-purchase paths.
