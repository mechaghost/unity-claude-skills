# Server-side IAP validation cookbook

Implementation detail for Apple App Store Server API + JWS / x5c verification, and Google Play Developer API + Pub/Sub RTDN. SKILL.md keeps the "what"/"why"; this file keeps the step-by-step "how".

## Apple App Store Server API setup

### Endpoints

- Production: `https://api.storekit.itunes.apple.com`
- Sandbox: `https://api.storekit-stage.itunes.apple.com`

The notification's `environment` field (or which store the client transacted against) selects the base URL — no `21007` retry like the deprecated `verifyReceipt` flow.

### Common reads

- Single transaction lookup: `GET /inApps/v1/transactions/{transactionId}` — returns signed JWS-encoded transaction. Verify `bundleId`, `productId`, transaction uniqueness (store `originalTransactionId`).
- Subscription state: `GET /inApps/v1/subscriptions/{originalTransactionId}` — Get All Subscription Statuses. Canonical renewal/grace/billing-retry state.

### ES256 JWT auth (every request)

Short-lived ES256 JWT in `Authorization: Bearer <jwt>`.

1. App Store Connect > **Users and Access > Keys > In-App Purchase**, generate key, download `.p8` (one-time download — secrets manager). Note **Key ID** (`kid`) and **Issuer ID** (`iss`).
2. JWT header:
   ```json
   { "alg": "ES256", "kid": "<your key ID>", "typ": "JWT" }
   ```
3. JWT payload (max 20-min lifetime):
   ```json
   {
     "iss": "<your issuer ID>",
     "iat": <unix-now>,
     "exp": <unix-now + 1200>,
     "aud": "appstoreconnect-v1",
     "bid": "<your bundle ID>"
   }
   ```
4. Sign with `.p8` using ES256 (ECDSA P-256 + SHA-256).
5. Send as `Authorization: Bearer <jwt>`. Cache JWT for its lifetime.

### Server-side validation pseudo-code (Apple)

```python
# Pseudo-code; pick a JWT lib that supports ES256 (jsonwebtoken, PyJWT, jose, ...).
def fetch_transaction(transaction_id, environment):
    base = APPLE_PROD if environment == "Production" else APPLE_SANDBOX
    jwt = mint_apple_jwt()  # see steps 2-4 above; cache for ~15min
    resp = http_get(
        f"{base}/inApps/v1/transactions/{transaction_id}",
        headers={"Authorization": f"Bearer {jwt}"},
    )
    signed_jws = resp.json()["signedTransactionInfo"]
    payload = verify_apple_jws(signed_jws)  # see App Store Server Notifications V2 below
    assert payload["bundleId"] == EXPECTED_BUNDLE_ID
    assert payload["productId"] in KNOWN_PRODUCT_IDS
    return payload  # contains originalTransactionId, transactionId, productId, ...
```

### App Store Server Notifications V2 (refund/renewal webhooks)

JWS compact-form payload (`header.payload.signature`). Verification mandatory before trusting body.

1. Decode JWS header (base64url), extract `x5c` cert chain (array of base64-DER, leaf first).
2. Leaf cert verifies the signature.
3. Verify chain ends at Apple's root CA. Pin Apple's root from https://www.apple.com/certificateauthority/, rotate annually.
4. Verify `alg = ES256`. Reject `none`, `RS256`, anything else.
5. Only after chain validates, parse and trust payload.

Notification types to handle: `REFUND`, `REVOKE`, `CONSUMPTION_REQUEST`, `DID_RENEW`, `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `PRICE_INCREASE`, `DID_CHANGE_RENEWAL_STATUS`, `SUBSCRIBED`.

```python
def verify_apple_jws(jws_compact):
    header_b64, payload_b64, sig_b64 = jws_compact.split(".")
    header = json.loads(base64url_decode(header_b64))
    if header["alg"] != "ES256":
        raise InvalidAlg(header["alg"])  # never accept "none" / RS256
    x5c = [der_to_cert(base64.b64decode(c)) for c in header["x5c"]]
    leaf, *intermediates = x5c
    if not chain_validates_to_apple_root(leaf, intermediates, APPLE_ROOT_CA):
        raise InvalidChain()
    if not leaf.public_key().verify_es256(
        sig=base64url_decode(sig_b64),
        msg=f"{header_b64}.{payload_b64}".encode(),
    ):
        raise BadSignature()
    return json.loads(base64url_decode(payload_b64))
```

### Apple idempotency / dedupe key

- Primary: `originalTransactionId` (covers original + every auto-renewal).
- Pair with `transactionId` to distinguish renewals from original.
- Store granted txIDs in unique-indexed table — second arrival no-ops.

## Google Play Developer API setup

### Service account

1. In the GCP project linked to Play Console, create a service account.
2. Grant **Android Publisher** API access in Play Console > Setup > API access (link GCP project, grant "View financial data, orders, and cancellation survey responses" minimum).
3. Download service-account JSON (one-time — secrets manager).
4. OAuth scope: `https://www.googleapis.com/auth/androidpublisher`.

### REST endpoints

- Products: `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{token}`
- Subscriptions V2: `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}`
- Voided purchases: `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/voidedpurchases`

`purchases.products.get` / `purchases.subscriptionsv2.get` are SDK shorthand.

### Acknowledgement deadline

Google requires acknowledgement within 3 days or auto-refunds. Don't leave validated `PendingOrder` unconfirmed — server flow triggers acknowledgement, or client calls `StoreController.ConfirmPurchase(order)` before deadline.

### Server-side validation pseudo-code (Google)

```python
def validate_play_purchase(package_name, product_id, purchase_token, product_type):
    creds = service_account_credentials_from_json(SA_JSON)
    creds = creds.with_scopes(["https://www.googleapis.com/auth/androidpublisher"])
    creds.refresh(Request())
    headers = {"Authorization": f"Bearer {creds.token}"}

    if product_type == "subscription":
        url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3"
               f"/applications/{package_name}/purchases/subscriptionsv2/tokens/{purchase_token}")
    else:
        url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3"
               f"/applications/{package_name}/purchases/products/{product_id}/tokens/{purchase_token}")

    resp = http_get(url, headers=headers)
    body = resp.json()
    # purchaseState 0 = purchased; consumptionState 1 = consumed (consumable only)
    assert body.get("purchaseState", 0) == 0
    return body
```

### Google idempotency / dedupe key

- Primary: `purchaseToken`. Unique-indexed table.
- Pub/Sub also delivers `messageId` — dedupe webhooks by it (Pub/Sub is at-least-once, not exactly-once).

## Google Pub/Sub Real-time Developer Notifications (RTDN)

Refund / renewal / cancel notifications via Pub/Sub topic in your GCP project.

### Setup

1. In the GCP project linked to Play Console, create a Pub/Sub topic (e.g. `play-rtdn`).
2. Grant `roles/pubsub.publisher` to `google-play-developer-notifications@system.gserviceaccount.com` — **on the topic**, not project level.
3. Subscription:
   - **Push** — HTTPS endpoint with OIDC auth token Pub/Sub mints; endpoint verifies on each delivery.
   - **Pull** — backend pulls from a worker.
4. Play Console > Monetization setup > Real-time developer notifications, set topic to `projects/{your-gcp-project}/topics/play-rtdn`. "Send Test Notification" to confirm.

### Message payload

Pub/Sub wraps the notification — base64-decode `message.data`:

```json
{
  "version": "1.0",
  "packageName": "com.studio.game",
  "eventTimeMillis": "1730000000000",
  "subscriptionNotification": {
    "version": "1.0",
    "notificationType": 4,
    "purchaseToken": "abc...",
    "subscriptionId": "pro_monthly"
  }
}
```

`notificationType` (subscriptions): 1 RECOVERED, 2 RENEWED, 3 CANCELED, 4 PURCHASED, 5 ON_HOLD, 6 IN_GRACE_PERIOD, 7 RESTARTED, 8 PRICE_CHANGE_CONFIRMED, 9 DEFERRED, 10 PAUSED, 11 PAUSE_SCHEDULE_CHANGED, 12 REVOKED, 13 EXPIRED. (Product / one-time uses `oneTimeProductNotification` with its own types.)

### Dedupe + handling

- Dedupe by Pub/Sub `messageId`.
- On `REVOKED` / `CANCELED` / `EXPIRED`: revoke entitlement server-side. Client syncs entitlements from server before unlocking gated content on boot.
- For consumable refunds, RTDN doesn't cover all cases — also poll **voided-purchases API** (`/applications/{packageName}/purchases/voidedpurchases`) on a daily job.

## Cross-platform end-to-end flow

```
client StoreController.Purchase(product)
  -> Unity IAP v5 OnPurchasePending(PendingOrder)
  -> client POST {order receipt/JWS, productId, userId} -> backend
  -> backend mints store JWT/token, calls App Store Server API or Play Developer API
  -> backend verifies bundleId/packageName + productId match expectations
  -> backend INSERT INTO entitlements (txId UNIQUE) VALUES (...) -- idempotency
  -> backend responds OK -> client StoreController.ConfirmPurchase(order)
  -> grant in-game item AFTER entitlement row exists server-side
```

If server says no, do NOT confirm. Keep retry state explicit; surface "purchase pending validation" rather than double-grant.

## Environment / staging

- Apple has separate sandbox + production base URLs; same `.p8` signs JWTs for both.
- Play has no separate base URL; license testers + internal testing track exercise the same API + RTDN topic. Static response IDs (`android.test.purchased`, `android.test.canceled`) bypass Play — only client-side smoke tests.
