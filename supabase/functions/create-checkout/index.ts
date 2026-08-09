// create-checkout — starts a PayMongo Checkout Session for Aumazing Premium.
//
// Called by the app (authenticated; JWT verified by the platform). Creates
// a hosted checkout session on PayMongo, records a pending payment row, and
// returns the checkout URL for the in-app WebView. The PayMongo secret key
// never ships in the app — it lives only in this function's secrets.
//
// Secrets required (supabase secrets set ...):
//   PAYMONGO_SECRET_KEY  — sk_test_... (sandbox)

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Premium Monthly — ₱149/month (manuscript Table 3.8), in centavos.
const PREMIUM_AMOUNT_CENTAVOS = 14900;

// Sentinel URLs watched by the app's checkout WebView; they never need to
// resolve to a real page.
const SUCCESS_URL = "https://aumazing.app/payment/success";
const CANCEL_URL = "https://aumazing.app/payment/cancel";

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
                name: "Aumazing Premium — 30 days",
                amount: PREMIUM_AMOUNT_CENTAVOS,
                currency: "PHP",
                quantity: 1,
              },
            ],
            payment_method_types: ["card", "gcash", "grab_pay", "paymaya"],
            description:
              "Aumazing Premium — 30 days of access, no auto-renewal (sandbox)",
            success_url: SUCCESS_URL,
            cancel_url: CANCEL_URL,
            send_email_receipt: false,
            metadata: { user_id: user.id },
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
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { error: insertError } = await admin.from("payment_records").insert({
    user_id: user.id,
    checkout_session_id: sessionId,
    amount: PREMIUM_AMOUNT_CENTAVOS,
    currency: "PHP",
    status: "pending",
  });
  if (insertError) {
    // The webhook can still resolve the user from session metadata, so a
    // failed pending row is logged but not fatal.
    console.error("payment_records insert failed:", insertError);
  }

  return json({ checkout_url: checkoutUrl, checkout_session_id: sessionId });
});
