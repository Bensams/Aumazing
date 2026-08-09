# Supabase Edge Functions

PayMongo sandbox integration for the Premium subscription (manuscript
FR-10, FR-17, NFR-06, Use Cases 12 & 13). Two functions:

| Function | Auth | Purpose |
| --- | --- | --- |
| `create-checkout` | Supabase JWT (default) | Creates a PayMongo Checkout Session (₱149/month, cards + GCash + GrabPay + Maya), records a pending `payment_records` row, returns the hosted `checkout_url` for the in-app WebView. |
| `paymongo-webhook` | PayMongo HMAC signature (deploy with `--no-verify-jwt`) | Verifies the `Paymongo-Signature` header, dedupes on event id via `webhook_events`, grants a 30-day `entitlements` period (`is_premium` + `expires_at`; paying again extends the running period) on `checkout_session.payment.paid`, revokes on refund events. There is no auto-renewal — expiry is enforced by `expires_at`, which clients cache and check locally (works offline). |

There is also an account-lifecycle function:

| Function | Auth | Purpose |
| --- | --- | --- |
| `delete-account` | Supabase JWT (default) | Permanently deletes the calling user: removes their `children` rows plus child-keyed `assessment_results` / `game_sessions` / `module_recommendations`, then deletes the auth user (FK cascades clean up `entitlements`, `payment_records`, `research_consents`). Refuses admin accounts. Called from Settings → Delete Account after a two-step confirmation. Deploy with `supabase functions deploy delete-account`. |

The app never talks to PayMongo directly and can never grant itself
Premium — entitlement rows are written only here with the service role.

## One-time setup

1. Apply the migrations `supabase/migrations/20260703_paymongo_entitlements.sql`
   and `supabase/migrations/20260720_entitlement_expiry.sql`
   (`supabase db push`).

2. Set the function secrets (PayMongo Dashboard → Developers → API Keys,
   **test mode**):

   ```sh
   supabase secrets set PAYMONGO_SECRET_KEY=sk_test_xxxxxxxx
   ```

3. Deploy:

   ```sh
   supabase functions deploy create-checkout
   supabase functions deploy paymongo-webhook --no-verify-jwt
   ```

4. Create the webhook (PayMongo Dashboard → Developers → Webhooks, test
   mode) pointing to:

   ```
   https://<project-ref>.supabase.co/functions/v1/paymongo-webhook
   ```

   Events: `checkout_session.payment.paid`, `payment.refunded`.
   Copy the webhook's signing secret (`whsk_...`) and set it:

   ```sh
   supabase secrets set PAYMONGO_WEBHOOK_SECRET=whsk_xxxxxxxx
   ```

## Testing the flow (sandbox)

- In the app: Parent Dashboard → Upgrade → pay inside the WebView with a
  PayMongo test card, e.g. `4343 4343 4343 4345`, any future expiry, any
  CVC (or the GCash/Maya test flows).
- Expected: webhook fires → `webhook_events` row (signature_valid = true,
  processed = true) → `payment_records.status = 'paid'` →
  `entitlements.is_premium = true` → the app's success dialog appears
  within the 20 s activation poll.
- Replay safety: redelivering the same event id is a no-op (200
  "already processed").
