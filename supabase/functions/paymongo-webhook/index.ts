// paymongo-webhook — PayMongo event receiver; the ONLY writer of Premium
// entitlements (NFR-06: signature verified before any grant).
//
// Deploy with --no-verify-jwt (PayMongo cannot send a Supabase JWT); the
// HMAC signature in the Paymongo-Signature header is the authentication.
// Events are logged to webhook_events and deduped on the PayMongo event id,
// so redeliveries and replays are no-ops (manuscript R-04, R-09).
//
// This file is deliberately thin: it verifies, loads state, calls the pure
// `decide` in ../_shared/payment_outcomes.ts, and hands the single effect
// that decision returns to `apply_payment_outcome`, which commits the
// payment transition and the entitlement effect in ONE database
// transaction under a row lock. Every outcome rule — grant, failure,
// cancellation, expiry, refund, ordering and ownership — lives in that
// module and is unit-tested there (AUM-168).
//
// Secrets required (supabase secrets set ...):
//   PAYMONGO_WEBHOOK_SECRET — whsk_... from the PayMongo webhook you create

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  decide,
  type Decision,
  parseEvent,
  type ParsedEvent,
  type PaymentStatus,
  type StoredEntitlement,
  type StoredPayment,
} from "../_shared/payment_outcomes.ts";
import { verifySignature } from "../_shared/paymongo_signature.ts";

function toDate(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const secret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET");
  if (!secret) {
    console.error("PAYMONGO_WEBHOOK_SECRET is not set");
    return new Response("webhook not configured", { status: 500 });
  }

  const rawBody = await req.text();
  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch {
    // Unparseable body: no event id to dedupe on, nothing to log against.
    return new Response("invalid payload", { status: 400 });
  }

  const now = new Date();
  const event: ParsedEvent | null = parseEvent(body, now);

  // Signature is checked against the livemode flag we can read off the
  // raw payload, so a malformed event still gets a real verification
  // attempt rather than being waved through.
  // deno-lint-ignore no-explicit-any
  const rawLivemode = (body as any)?.data?.attributes?.livemode === true;
  const signatureValid = await verifySignature(
    req.headers.get("paymongo-signature"),
    rawBody,
    event?.livemode ?? rawLivemode,
    secret,
  );

  if (!signatureValid) {
    // An unverified caller must produce NO database side effects at all.
    // The previous version upserted a webhook_events row here, which let
    // anyone who could reach the URL write unbounded rows — and, worse,
    // occupy an event_id so the genuine signed delivery of that same id
    // would later be dropped as a duplicate.
    console.error(
      `Rejected webhook ${event?.eventId ?? "?"}: bad signature`,
    );
    return new Response("invalid signature", { status: 401 });
  }

  // Signed but not shaped like an event we understand. Acknowledge so
  // PayMongo stops retrying; write nothing.
  if (!event) {
    console.error("Signed webhook with malformed payload; ignoring");
    return new Response("ok", { status: 200 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Dedupe on the PayMongo event id: if the row already exists this is a
  // redelivery/replay — acknowledge without reprocessing. This is the
  // cheap first line of defence; `decide` plus `apply_payment_outcome`
  // independently guard against a second *distinct* event id for the
  // same purchase.
  const { data: inserted, error: logError } = await admin
    .from("webhook_events")
    .upsert(
      {
        event_id: event.eventId,
        event_type: event.eventType,
        signature_valid: true,
        payload: body,
        processed: false,
      },
      { onConflict: "event_id", ignoreDuplicates: true },
    )
    .select("id");
  if (logError) {
    console.error("webhook_events insert failed:", logError);
    return new Response("storage error", { status: 500 });
  }
  let logId: string;
  if (inserted && inserted.length > 0) {
    logId = inserted[0].id;
  } else {
    // A prior attempt may have failed after inserting its unprocessed row.
    // Reuse that row so cleanup failures remain retryable instead of being
    // acknowledged as a duplicate forever.
    const { data: existing, error: existingError } = await admin
      .from("webhook_events")
      .select("id, processed")
      .eq("event_id", event.eventId)
      .maybeSingle();
    if (existingError) {
      console.error("webhook_events dedupe lookup failed:", existingError);
      return new Response("storage error", { status: 500 });
    }
    if (!existing || existing.processed === true) {
      return new Response("already processed", { status: 200 });
    }
    logId = existing.id;
  }

  // Every early return past this point deletes the log row first, so
  // PayMongo's retry is not dropped as a duplicate of a delivery we never
  // finished handling.
  const retryable = async (message: string, detail: unknown) => {
    console.error(message, detail);
    const { error: cleanupError } = await admin
      .from("webhook_events")
      .delete()
      .eq("id", logId);
    if (cleanupError) {
      // Leave processed=false when cleanup fails; the next delivery will
      // reclaim this row through the unprocessed-dedupe path above.
      console.error("webhook_events cleanup failed; retry remains enabled:", cleanupError);
    }
    return new Response("storage error", { status: 500 });
  };

  // Load the stored payment this event claims to be about. The session id
  // is the binding key written by create-checkout; without a match we
  // have no verified owner and `decide` refuses to grant.
  let payment: StoredPayment | null = null;
  if (event.sessionId) {
    const { data: row, error: paymentError } = await admin
      .from("payment_records")
      .select(
        "id, user_id, checkout_session_id, amount, currency, status, updated_at",
      )
      .eq("checkout_session_id", event.sessionId)
      .maybeSingle();
    if (paymentError) {
      return await retryable("payment_records lookup failed:", paymentError);
    }
    if (row) {
      payment = {
        id: row.id,
        userId: row.user_id,
        checkoutSessionId: row.checkout_session_id,
        amount: row.amount,
        currency: row.currency,
        status: row.status as PaymentStatus,
        updatedAt: toDate(row.updated_at),
      };
    }
  }

  let entitlement: StoredEntitlement | null = null;
  if (payment) {
    const { data: row, error: entitlementError } = await admin
      .from("entitlements")
      .select("user_id, is_premium, activated_at, updated_at")
      .eq("user_id", payment.userId)
      .maybeSingle();
    if (entitlementError) {
      return await retryable("entitlements lookup failed:", entitlementError);
    }
    if (row) {
      entitlement = {
        userId: row.user_id,
        isPremium: row.is_premium === true,
        activatedAt: toDate(row.activated_at),
        updatedAt: toDate(row.updated_at),
      };
    }
  }

  const decision: Decision = decide({ event, payment, entitlement, now });

  // The decision authorises at most one write, and that write is applied
  // as a single transaction: the payment transition and the entitlement
  // effect commit together or not at all. The function locks the payment
  // row and re-checks the status the decision was reasoned about, so of
  // two concurrent deliveries for one purchase exactly one applies —
  // the loser gets `applied: false` and grants nothing.
  let outcome = "no_effect";
  if (decision.apply) {
    const a = decision.apply;
    const { data: result, error } = await admin.rpc("apply_payment_outcome", {
      p_payment_id: a.paymentId,
      p_user_id: a.userId,
      p_expected_status: a.expectedStatus,
      p_new_status: a.newStatus,
      p_effect: a.effect,
      p_source: a.source,
      p_at: a.at.toISOString(),
    });
    if (error) {
      // Nothing was committed — the transaction rolled back — so a retry
      // sees the original state and can complete the whole outcome.
      return await retryable("apply_payment_outcome failed:", error);
    }
    const applied = (result as { applied?: boolean } | null)?.applied === true;
    outcome = applied
      ? "applied"
      : `not_applied:${(result as { reason?: string } | null)?.reason ?? "?"}`;
    // A refused application is a correct, expected outcome (a concurrent
    // winner already settled it) — but it is NOT this delivery's success,
    // so it must not be recorded as one.
    if (!applied) {
      await admin
        .from("webhook_events")
        .update({ processed: false })
        .eq("id", logId);
      console.log(
        `Webhook ${event.eventId} (${event.eventType}): ` +
          `${decision.reason} → ${outcome}`,
      );
      return new Response("ok", { status: 200 });
    }
  }

  await admin
    .from("webhook_events")
    .update({ processed: decision.processed })
    .eq("id", logId);

  console.log(
    `Webhook ${event.eventId} (${event.eventType}): ${decision.reason} → ${outcome}`,
  );
  return new Response("ok", { status: 200 });
});
