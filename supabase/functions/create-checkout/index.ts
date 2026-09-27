// create-checkout — starts a PayMongo Checkout Session for Aumazing Premium,
// or for one extra child profile (`product: "profile_slot"`, AUM-349), which
// only accounts with active Premium may buy.
//
// Called by the app (authenticated; JWT verified by the platform). Creates
// a hosted checkout session on PayMongo, records a pending payment row, and
// returns the checkout URL. The PayMongo secret key never ships in the app —
// it lives only in this function's secrets.
//
// The Android/iOS app opens checkout in an in-app WebView that watches for the
// sentinel URLs below. The web app instead sends the parent to checkout in the
// same browser tab, so it passes `return_url` (its own address) and PayMongo
// brings the parent back there with `?payment=success` or
// `?payment=cancelled`.
//
// Secrets required (supabase secrets set ...):
//   PAYMONGO_SECRET_KEY  — sk_test_... (sandbox)
// Optional:
//   ALLOWED_RETURN_ORIGINS — comma-separated origins the web app may return
//     to (default: the GitHub Pages site, plus localhost for development).

import { createClient } from "npm:@supabase/supabase-js@2";
import { allowedReturnUrl, withOutcome } from "../_shared/return_url.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// What each product costs and how it reads on the PayMongo page. Amounts in
// centavos. Premium Monthly — ₱149/month (manuscript Table 3.8); an extra
// child profile — ₱30, once (AUM-343).
const PRODUCTS = {
  premium: {
    amount: 14900,
    name: "Aumazing Premium — 30 days",
    description:
      "Aumazing Premium — 30 days of access, no auto-renewal (sandbox)",
  },
  profile_slot: {
    amount: 3000,
    name: "Aumazing extra child profile",
    description: "One extra child profile on your account, one-time (sandbox)",
  },
} as const;
type Product = keyof typeof PRODUCTS;

// Sentinel URLs watched by the app's checkout WebView; they never need to
// resolve to a real page.
const SUCCESS_URL = "https://aumazing.app/payment/success";
const CANCEL_URL = "https://aumazing.app/payment/cancel";

const DEFAULT_RETURN_ORIGINS = ["https://bensams.github.io"];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // Resolve the calling user from their JWT (RLS-scoped client).
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } =
    await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "not authenticated" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const allowedOrigins = (Deno.env.get("ALLOWED_RETURN_ORIGINS") ?? "")
    .split(",").map((o) => o.trim()).filter(Boolean);
  const returnUrl = allowedReturnUrl(
    body?.return_url,
    allowedOrigins.length > 0 ? allowedOrigins : DEFAULT_RETURN_ORIGINS,
  );
  if (body?.return_url !== undefined && returnUrl === null) {
    return json({ error: "return_url not allowed" }, 400);
  }
  const product: Product = body?.product === "profile_slot"
    ? "profile_slot"
    : "premium";
  if (body?.product !== undefined && body.product !== product) {
    return json({ error: "unknown product" }, 400);
  }
  const item = PRODUCTS[product];

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  // Extra child profiles are a Premium feature (AUM-343): refuse before the
  // parent is sent to pay for something they could not use.
  if (product === "profile_slot") {
    const { data: premium, error: premiumError } = await admin.rpc(
      "has_active_premium",
      { p_user_id: user.id },
    );
    if (premiumError) {
      console.error("has_active_premium failed:", premiumError);
      return json({ error: "could not create checkout session" }, 500);
    }
    if (premium !== true) {
      return json({ error: "premium required" }, 403);
    }
  }

  const successUrl = returnUrl ? withOutcome(returnUrl, "success") : SUCCESS_URL;
  const cancelUrl = returnUrl ? withOutcome(returnUrl, "cancelled") : CANCEL_URL;

  const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
  if (!secretKey) {
    console.error("PAYMONGO_SECRET_KEY is not set");
    return json({ error: "payment gateway not configured" }, 500);
  }

  // Create the hosted checkout session (cards, GCash, GrabPay, Maya — FR-10).
  const paymongoResponse = await fetch(
    "https://api.paymongo.com/v1/checkout_sessions",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${secretKey}:`)}`,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            line_items: [
              {
                name: item.name,
                amount: item.amount,
                currency: "PHP",
                quantity: 1,
              },
            ],
            payment_method_types: ["card", "gcash", "grab_pay", "paymaya"],
            description: item.description,
            success_url: successUrl,
            cancel_url: cancelUrl,
            send_email_receipt: false,
            metadata: { user_id: user.id, product },
          },
        },
      }),
    },
  );

  const paymongoBody = await paymongoResponse.json();
  if (!paymongoResponse.ok) {
    console.error("PayMongo checkout_sessions failed:", paymongoBody);
    return json({ error: "could not create checkout session" }, 502);
  }

  const sessionId = paymongoBody?.data?.id as string | undefined;
  const checkoutUrl =
    paymongoBody?.data?.attributes?.checkout_url as string | undefined;
  if (!sessionId || !checkoutUrl) {
    console.error("Unexpected PayMongo response shape:", paymongoBody);
    return json({ error: "could not create checkout session" }, 502);
  }

  // Record the pending payment (service role — clients cannot write here).
  // `product` is what the webhook trusts when deciding the effect.
  const { error: insertError } = await admin.from("payment_records").insert({
    user_id: user.id,
    checkout_session_id: sessionId,
    amount: item.amount,
    currency: "PHP",
    status: "pending",
    product,
  });
  if (insertError) {
    // This row is the ONLY trusted binding between a PayMongo session and
    // an account: the webhook refuses to grant Premium for a session it
    // cannot find here, because session metadata is attacker-shaped input
    // rather than something we wrote. Without the row a completed payment
    // would strand the parent with no entitlement, so fail the checkout
    // now — before they are sent to the payment page — instead of taking
    // money we cannot honour.
    console.error("payment_records insert failed:", insertError);
    return json({ error: "could not create checkout session" }, 500);
  }

  return json({ checkout_url: checkoutUrl, checkout_session_id: sessionId });
});
