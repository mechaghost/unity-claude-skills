# Server-side IAP validation cookbook

Full implementation detail for Apple App Store Server API + JWS / x5c verification, and Google Play Developer API + Pub/Sub Real-time Developer Notifications. The `unity-iap` SKILL.md keeps the "what" and "why"; this file keeps the step-by-step "how".

## Apple App Store Server API setup

### Endpoints

- Production: `https://api.storekit.itunes.apple.com`
- Sandbox: `https://api.storekit-stage.itunes.apple.com`

The notification's `environment` field (or which store the client transacted against) tells you which base URL to hit — there is no `21007` retry dance like on the deprecated `verifyReceipt` flow.

### Common reads

- Single transaction lookup (verify a client receipt):
  `GET /inApps/v1/transactions/{transactionId}` — returns a signed JWS-encoded transaction. Verify `bundleId`, `productId`, transaction uniqueness (store `originalTransactionId`).
- Subscription state:
  `GET /inApps/v1/subscriptions/{originalTransactionId}` — Get All Subscription Statuses. Use this for canonical renewal/grace/billing-retry state, not the local receipt.

### ES256 JWT auth (required on every request)

App Store Server API requires a short-lived ES256 JWT in the `Authorization: Bearer <jwt>` header.

1. From App Store Connect, go to **Users and Access > Keys > In-App Purchase**, generate a key, and download the `.p8` private key file (one-time download — store it in your secrets manager). Note the **Key ID** (`kid`) and **Issuer ID** (`iss`) from that page.
2. Build the JWT header:
   ```json
   { "alg": "ES256", "kid": "<your key ID>", "typ": "JWT" }
   ```
3. Build the JWT payload (max 20-minute lifetime; rotate aggressively):
   ```json
   {
     "iss": "<your issuer ID>",
     "iat": <unix-now>,
     "exp": <unix-now + 1200>,
     "aud": "appstoreconnect-v1",
     "bid": "<your bundle ID>"
   }
   ```
4. Sign with the `.p8` private key using ES256 (ECDSA on P-256 with SHA-256).
5. Send as `Authorization: Bearer <jwt>` on every request. Cache the JWT for its lifetime; do not regenerate per call.

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

The HTTPS endpoint receives a JWS compact-form payload (`header.payload.signature`). Verification is mandatory before trusting the body.

1. Decode the JWS header (base64url) and extract the `x5c` cert chain (array of base64-DER certs, leaf first).
2. The leaf cert in `x5c` verifies the JWS signature.
3. Verify the cert chain ends at Apple's root CA. Download Apple's root from their PKI page (https://www.apple.com/certificateauthority/), pin the root in your service, and rotate annually.
4. Verify `alg = ES256` in the header. Reject anything else — never accept `none`, `RS256`, or unexpected algs.
5. Only after the chain validates do you parse and trust the payload.

Notification types you need to handle: `REFUND`, `REVOKE`, `CONSUMPTION_REQUEST`, `DID_RENEW`, `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `PRICE_INCREASE`, `DID_CHANGE_RENEWAL_STATUS`, `SUBSCRIBED`.

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

- Primary: `originalTransactionId` (covers the original purchase + every auto-renewal that shares it).
- Pair with `transactionId` when distinguishing renewals from the original.
- Store granted txIDs in a unique-indexed table. Second arrival of the same txID returns the existing entitlement row and is a no-op — never grants twice.

## Google Play Developer API setup

### Service account

1. In the Google Cloud project linked to your Play Console, create a service account.
2. Grant it the **Android Publisher** API access in the Play Console > Setup > API access page (link the GCP project, then grant "View financial data, orders, and cancellation survey responses" at minimum; fuller access for subscriptions and voided purchases).
3. Download the service-account JSON (one-time download — store in secrets manager).
4. Required OAuth scope when minting access tokens from the JSON: `https://www.googleapis.com/auth/androidpublisher`.

### REST endpoints

- Products (consumables / non-consumables):
  `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{token}`
- Subscriptions V2 (current canonical):
  `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}`
- Voided purchases (poll for refund-with-revoke on consumables):
  `GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/voidedpurchases`

`purchases.products.get` / `purchases.subscriptionsv2.get` are SDK shorthand for these REST paths.

### Acknowledgement deadline

Google requires acknowledgement within 3 days or auto-refunds. Unity IAP acknowledges on `Complete` but NOT on `Pending` — the server flow must trigger acknowledgement (or trigger client `ConfirmPendingPurchase`) before the deadline.

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

- Primary: `purchaseToken`. Server stores granted tokens in a unique-indexed table.
- Pub/Sub also delivers a `messageId` — dedupe webhook deliveries by `messageId` (Pub/Sub guarantees at-least-once, not exactly-once).

## Google Pub/Sub Real-time Developer Notifications (RTDN)

Refund / renewal / cancel notifications arrive via a Pub/Sub topic in your GCP project.

### Setup steps

1. In the same GCP project that's linked to your Play Console, create a Pub/Sub topic (e.g. `play-rtdn`).
2. Grant the role `roles/pubsub.publisher` to the well-known service account that Play uses to publish:
   `google-play-developer-notifications@system.gserviceaccount.com` — granted **on the topic**, not at project level.
3. Create a subscription:
   - **Push** subscription: HTTPS endpoint with an OIDC auth token Pub/Sub will mint and your endpoint will verify on each delivery.
   - **Pull** subscription: your backend pulls from Pub/Sub on a worker.
4. In Play Console > Monetization setup > Real-time developer notifications, set the topic to `projects/{your-gcp-project}/topics/play-rtdn`. Hit "Send Test Notification" to confirm delivery.

### Message payload shape

Pub/Sub wraps the notification — base64-decode `message.data` to get the JSON envelope:

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

`notificationType` values (subscriptions): 1 RECOVERED, 2 RENEWED, 3 CANCELED, 4 PURCHASED, 5 ON_HOLD, 6 IN_GRACE_PERIOD, 7 RESTARTED, 8 PRICE_CHANGE_CONFIRMED, 9 DEFERRED, 10 PAUSED, 11 PAUSE_SCHEDULE_CHANGED, 12 REVOKED, 13 EXPIRED. (Product / one-time notifications use a `oneTimeProductNotification` field with its own type values.)

### Dedupe + handling

- Dedupe by Pub/Sub `messageId` (Pub/Sub guarantees at-least-once).
- On `REVOKED` / `CANCELED` / `EXPIRED`: revoke entitlement server-side. On client app boot, sync entitlements from server before unlocking gated content.
- For consumable refunds, RTDN does NOT cover all cases — also poll the **voided-purchases API** (`/applications/{packageName}/purchases/voidedpurchases`) on a daily job and reconcile.

## Cross-platform end-to-end flow

```
client.InitiatePurchase
  -> Unity IAP ProcessPurchase fires (PurchaseProcessingResult.Pending)
  -> client POST {receipt, productId, userId} -> backend
  -> backend mints store JWT/token, calls App Store Server API or Play Developer API
  -> backend verifies bundleId/packageName + productId match expectations
  -> backend INSERT INTO entitlements (txId UNIQUE) VALUES (...) -- idempotency
  -> backend responds OK -> client.ConfirmPendingPurchase(product)
  -> grant in-game item AFTER entitlement row exists server-side
```

If the server says no, do NOT call `ConfirmPendingPurchase` — Unity IAP will re-deliver on next launch and you can retry.

## Environment / staging

- App Store Server API has separate sandbox + production base URLs; the same `.p8` key signs JWTs for both.
- Play has no separate base URL; license testers + internal testing track exercise the same API and same RTDN topic. Static response IDs (`android.test.purchased`, `android.test.canceled`) bypass Play entirely and won't exercise webhooks — only useful for client-side smoke tests.
