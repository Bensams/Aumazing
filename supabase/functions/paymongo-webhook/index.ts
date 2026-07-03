// paymongo-webhook — PayMongo event receiver; the ONLY writer of Premium
// entitlements (NFR-06: signature verified before any grant).
//
// Deploy with --no-verify-jwt (PayMongo cannot send a Supabase JWT); the
// HMAC signature in the Paymongo-Signature header is the authentication.
// Events are logged to webhook_events and deduped on the PayMongo event id,
// so redeliveries and replays are no-ops (manuscript R-04, R-09).
//
// Secrets required (supabase secrets set ...):
//   PAYMONGO_WEBHOOK_SECRET — whsk_... from the PayMongo webhook you create

import { createClient } from "npm:@supabase/supabase-js@2";

const GRANT_EVENTS = ["checkout_session.payment.paid"];
const REVOKE_EVENTS = ["payment.refunded", "payment.refund.updated"];

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/// Paymongo-Signature: "t=<ts>,te=<test-mode sig>,li=<live-mode sig>".
/// The signed message is "<t>.<raw body>"; compare against te or li
/// depending on the event's livemode flag.
async function verifySignature(
  header: string | null,
  rawBody: string,
  livemode: boolean,
  secret: string,
): Promise<boolean> {
  if (!header) return false;
  const parts = new Map(
    header.split(",").map((p) => p.trim().split("=") as [string, string]),
  );
  const timestamp = parts.get("t");
  const expected = livemode ? parts.get("li") : parts.get("te");
  if (!timestamp || !expected) return false;
  const computed = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  return timingSafeEqual(computed, expected);
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
  let body: any;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return new Response("invalid payload", { status: 400 });
  }

  const event = body?.data;
  const eventId = event?.id as string | undefined;
  const eventType = event?.attributes?.type as string | undefined;
  const livemode = event?.attributes?.livemode === true;
  const resource = event?.attributes?.data; // e.g. the checkout session

  const signatureValid = await verifySignature(
    req.headers.get("paymongo-signature"),
    rawBody,
    livemode,
    secret,
  );

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (!signatureValid) {
    // Log the rejected delivery for the audit trail, grant nothing.
    await admin.from("webhook_events").upsert(
      {
        event_id: eventId,
        event_type: eventType,
        signature_valid: false,
        payload: body,
        processed: false,
      },
      { onConflict: "event_id", ignoreDuplicates: true },
    );
    console.error(`Rejected webhook ${eventId ?? "?"}: bad signature`);
    return new Response("invalid signature", { status: 401 });
  }

  // Dedupe on the PayMongo event id: if the row already exists this is a
  // redelivery/replay — acknowledge without reprocessing.
  const { data: inserted, error: logError } = await admin
    .from("webhook_events")
    .upsert(
      {
        event_id: eventId,
        event_type: eventType,
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
  if (!inserted || inserted.length === 0) {
    return new Response("already processed", { status: 200 });
  }
  const logId = inserted[0].id;

  let processed = false;
  const now = new Date().toISOString();

  if (eventType && GRANT_EVENTS.includes(eventType)) {
    const sessionId = resource?.id as string | undefined;
    let userId = resource?.attributes?.metadata?.user_id as string | undefined;
    if (!userId && sessionId) {
      const { data: record } = await admin
        .from("payment_records")
        .select("user_id")
        .eq("checkout_session_id", sessionId)
        .maybeSingle();
      userId = record?.user_id;
    }

    if (userId) {
      if (sessionId) {
        await admin
          .from("payment_records")
          .update({ status: "paid", updated_at: now })
          .eq("checkout_session_id", sessionId);
      }
      const { error: grantError } = await admin.from("entitlements").upsert({
        user_id: userId,
        is_premium: true,
        source: livemode ? "paymongo" : "paymongo_test",
        activated_at: now,
        updated_at: now,
      });
      if (grantError) {
        console.error("entitlement grant failed:", grantError);
      } else {
        processed = true;
        console.log(`Premium granted to ${userId} (event ${eventId})`);
      }
    } else {
      console.error(`No user for paid session ${sessionId} (event ${eventId})`);
    }
  } else if (eventType && REVOKE_EVENTS.includes(eventType)) {
    // Refund/chargeback (R-09): downgrade the account. The payment resource
    // carries the checkout metadata when created through a checkout session.
    const userId =
      resource?.attributes?.metadata?.user_id as string | undefined;
    if (userId) {
      const { error: revokeError } = await admin.from("entitlements").upsert({
        user_id: userId,
        is_premium: false,
        source: livemode ? "paymongo" : "paymongo_test",
        updated_at: now,
      });
      if (revokeError) {
        console.error("entitlement revoke failed:", revokeError);
      } else {
        processed = true;
        console.log(`Premium revoked for ${userId} (event ${eventId})`);
      }
    } else {
      console.error(`Refund event ${eventId} carries no user_id metadata`);
    }
  } else {
    // Unhandled event type: acknowledged, logged, nothing to do.
    processed = true;
  }

  await admin
    .from("webhook_events")
    .update({ processed })
    .eq("id", logId);

  return new Response("ok", { status: 200 });
});
