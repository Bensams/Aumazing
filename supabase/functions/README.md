# Supabase Edge Functions

PayMongo sandbox integration for the Premium subscription (manuscript
FR-10, FR-17, NFR-06, Use Cases 12 & 13). Two functions:

| Function | Auth | Purpose |
| --- | --- | --- |
| `create-checkout` | Supabase JWT (default) | Creates a PayMongo Checkout Session (₱149/month, cards + GCash + GrabPay + Maya), records a pending `payment_records` row, returns the hosted `checkout_url` for the in-app WebView. |
| `paymongo-webhook` | PayMongo HMAC signature (deploy with `--no-verify-jwt`) | Verifies the `Paymongo-Signature` header, dedupes on event id via `webhook_events`, grants Premium (`is_premium`) on `checkout_session.payment.paid`, revokes on refund events. |

### Payment outcome rules (AUM-168 — atomic grant/revoke only)

Every outcome decision lives in `_shared/payment_outcomes.ts` as pure
functions; `paymongo-webhook/index.ts` is a thin shell that verifies,
loads state, calls `decide()`, and applies the returned effects. The
rules are unit-tested in `tests/payment_outcomes_test.ts` — run with
`deno test supabase/functions/tests/`.

The guarantees that suite pins:

- **Grants are bound to a stored checkout.** A paid event only grants if
  a `payment_records` row matches its `checkout_session_id`. Event
  metadata is treated as a *claim*: if `metadata.user_id` disagrees with
  the stored owner, the event is rejected rather than applied to either
  account. Underpayment and currency mismatches do not grant.
- **Nothing negative touches an entitlement.** `payment.failed`,
  `checkout_session.expired`, and the cancelled/timed-out variants settle
  the payment row only.
- **Idempotency is keyed on the payment's state transition** (AUM-168),
  the event id. One purchase can emit two event ids
  (`checkout_session.payment.paid` and `payment.paid`); a grant applies
  only to a record that is not already `paid`, so Premium is never
  granted twice.
- **Out-of-order deliveries cannot corrupt newer state.** A late
  `expired` cannot undo a `paid` record; a refund of an older payment
  cannot revoke Premium a newer payment bought.
- **An invalid signature produces no database writes at all** (AUM-168),
  a `webhook_events` row, which previously let an unauthenticated caller
  occupy an `event_id` and get the genuine signed delivery dropped as a
  duplicate.

`payment_records.status` values: `pending` → `paid` | `failed` |
`cancelled` | `expired` | `refunded`.

There is also an account-lifecycle function (AUM-204 is separate):

| Function | Auth | Purpose |
| --- | --- | --- |
| `delete-account` | Supabase JWT (default) | Permanently deletes the calling user: removes their `children` rows plus child-keyed `assessment_results` / `game_sessions` / `module_recommendations`, then deletes the auth user (FK cascades clean up `entitlements`, `payment_records`, `research_consents`). Refuses admin accounts. Called from Settings → Delete Account after a two-step confirmation. Deploy with `supabase functions deploy delete-account`. |

The app never talks to PayMongo directly and can never grant itself
Premium — entitlement rows are written only here with the service role.

## One-time setup

1. Apply the migrations `supabase/migrations/20260703_paymongo_entitlements.sql`
   and `supabase/migrations/20260821_apply_payment_outcome.sql`
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
