// AUM-168 — payment outcome decisions.
//
// Covers the three acceptance criteria against the pure decision layer:
// an authentic paid event grants Premium to the right account only;
// failed/cancelled/expired/timed-out outcomes never grant; duplicate,
// delayed, out-of-order, malformed and invalid-signature deliveries are
// idempotent and safe.
//
// Run: deno test supabase/functions/tests/

import {
  assert,
  assertEquals,
  assertFalse,
} from "jsr:@std/assert@1";

import {
  decide,
  type Decision,
  parseEvent,
  type ParsedEvent,
  type StoredEntitlement,
  type StoredPayment,
} from "../_shared/payment_outcomes.ts";
import {
  hmacSha256Hex,
  verifySignature,
} from "../_shared/paymongo_signature.ts";

const NOW = new Date("2026-08-21T12:00:00.000Z");
const PARENT = "11111111-1111-1111-1111-111111111111";
const OTHER_PARENT = "22222222-2222-2222-2222-222222222222";
const SESSION = "cs_test_abc123";
const PRICE = 14900;

// A non-secret string used only to exercise the HMAC path in tests.
const TEST_SIGNING_KEY = "whsk_not_a_real_secret_for_tests_only";

function pendingPayment(overrides: Partial<StoredPayment> = {}): StoredPayment {
  return {
    id: "pay-row-1",
    userId: PARENT,
    checkoutSessionId: SESSION,
    amount: PRICE,
    currency: "PHP",
    status: "pending",
    updatedAt: new Date("2026-08-21T11:55:00.000Z"),
    ...overrides,
  };
}

function activeEntitlement(
  overrides: Partial<StoredEntitlement> = {},
): StoredEntitlement {
  return {
    userId: PARENT,
    isPremium: true,
    activatedAt: new Date("2026-08-01T00:00:00.000Z"),
    updatedAt: new Date("2026-08-01T00:00:00.000Z"),
    ...overrides,
  };
}

/// A realistically-shaped PayMongo event envelope.
function eventBody(
  type: string,
  opts: Record<string, unknown> = {},
): unknown {
  const {
    id = "evt_1",
    sessionId = SESSION as string | undefined,
    amount = PRICE as number | undefined,
    currency = "PHP" as string | undefined,
    createdAt = Math.floor(NOW.getTime() / 1000),
    livemode = false,
    status,
  } = opts;
  // Explicit `userId: undefined` must omit metadata, not fall back to PARENT.
  // Default parameters treat undefined as "missing", which hid owner-binding.
  const userId = Object.hasOwn(opts, "userId") ? opts.userId : PARENT;
  // deno-lint-ignore no-explicit-any
  const attributes: any = { metadata: {} };
  if (userId) attributes.metadata.user_id = userId;
  if (status) attributes.status = status;
  if (amount !== undefined) {
    attributes.payments = [{ attributes: { amount, currency } }];
  }
  return {
    data: {
      id,
      attributes: {
        type,
        livemode,
        created_at: createdAt,
        data: { id: sessionId, attributes },
      },
    },
  };
}

function parsed(type: string, opts: Record<string, unknown> = {}): ParsedEvent {
  const event = parseEvent(eventBody(type, opts), NOW);
  assert(event, `expected ${type} to parse`);
  return event;
}

function run(
  event: ParsedEvent,
  payment: StoredPayment | null,
  entitlement: StoredEntitlement | null = null,
): Decision {
  return decide({ event, payment, entitlement, now: NOW });
}

/// Negative paths and no-ops must never grant or revoke Premium.
function assertGrantsNothing(decision: Decision) {
  assertEquals(
    decision.apply?.effect ?? "none",
    "none",
    `expected no entitlement write, got ${JSON.stringify(decision)}`,
  );
}

// ───────────────────────── AC1: authentic payment grants ─────────────────

Deno.test("paid event grants Premium to the account that started checkout", () => {
  const decision = run(parsed("checkout_session.payment.paid"), pendingPayment());

  assertEquals(decision.reason, "granted");
  assert(decision.processed);
  assertEquals(decision.apply?.paymentId, "pay-row-1");
  assertEquals(decision.apply?.newStatus, "paid");
  assertEquals(decision.apply?.expectedStatus, "pending");
  assertEquals(decision.apply?.userId, PARENT);
  assertEquals(decision.apply?.effect, "grant");
  assertEquals(decision.apply?.source, "paymongo_test");
  assertEquals(decision.apply?.at.getTime(), NOW.getTime());
});

Deno.test("a live-mode grant is recorded as a live source", () => {
  const decision = run(
    parsed("checkout_session.payment.paid", { livemode: true }),
    pendingPayment(),
  );

  assertEquals(decision.apply?.source, "paymongo");
  assertEquals(decision.apply?.effect, "grant");
});

// ───────────── AC2: failed / cancelled / expired / timed out ─────────────

for (
  const [type, expected] of [
    ["payment.failed", "failed"],
    ["checkout_session.payment.failed", "failed"],
    ["checkout_session.expired", "expired"],
    ["payment.expired", "expired"],
    ["checkout_session.cancelled", "cancelled"],
    ["payment.cancelled", "cancelled"],
  ] as const
) {
  Deno.test(`${type} settles as ${expected} and grants nothing`, () => {
    const decision = run(parsed(type), pendingPayment());

    assertEquals(decision.apply?.newStatus, expected);
    assertEquals(decision.apply?.effect, "none");
    assertGrantsNothing(decision);
  });
}

Deno.test("a negative outcome never revokes an unrelated running period", () => {
  // The parent has Premium from an earlier purchase; a new checkout fails.
  const decision = run(parsed("payment.failed"), pendingPayment(), activeEntitlement());

  assertEquals(decision.apply?.newStatus, "failed");
  assertGrantsNothing(decision);
});

Deno.test("an unknown event type is acknowledged but changes nothing", () => {
  const decision = run(parsed("payment.awaiting_next_action"), pendingPayment());

  assert(decision.processed, "should be acknowledged so PayMongo stops retrying");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

// ─────────────── AC3: signatures, malformed payloads, replay ─────────────

Deno.test("a valid signature verifies and a tampered body does not", async () => {
  const rawBody = JSON.stringify(eventBody("checkout_session.payment.paid"));
  const timestamp = "1755777600";
  const signature = await hmacSha256Hex(
    TEST_SIGNING_KEY,
    `${timestamp}.${rawBody}`,
  );
  const header = `t=${timestamp},te=${signature},li=other`;

  assert(await verifySignature(header, rawBody, false, TEST_SIGNING_KEY));
  // Same signature, body changed by one character → rejected.
  assertFalse(
    await verifySignature(header, rawBody + " ", false, TEST_SIGNING_KEY),
  );
  // Right body, wrong secret → rejected.
  assertFalse(await verifySignature(header, rawBody, false, "whsk_wrong"));
});

Deno.test("signature verification rejects missing and malformed headers", async () => {
  const body = "{}";
  assertFalse(await verifySignature(null, body, false, TEST_SIGNING_KEY));
  assertFalse(await verifySignature("", body, false, TEST_SIGNING_KEY));
  // No timestamp component.
  assertFalse(await verifySignature("te=abc", body, false, TEST_SIGNING_KEY));
  // Garbage that would previously blow up the "=" split.
  assertFalse(
    await verifySignature("nonsense", body, false, TEST_SIGNING_KEY),
  );
  assertFalse(await verifySignature("t=1,,te", body, false, TEST_SIGNING_KEY));
});

Deno.test("a test-mode signature cannot authenticate a live-mode event", async () => {
  const rawBody = JSON.stringify(
    eventBody("checkout_session.payment.paid", { livemode: true }),
  );
  const timestamp = "1755777600";
  const testSig = await hmacSha256Hex(
    TEST_SIGNING_KEY,
    `${timestamp}.${rawBody}`,
  );
  // Correct HMAC, but presented in the test-mode slot for a live event.
  const header = `t=${timestamp},te=${testSig}`;

  assertFalse(await verifySignature(header, rawBody, true, TEST_SIGNING_KEY));
});

Deno.test("malformed payloads produce no event, so the shell writes nothing", () => {
  const malformed: unknown[] = [
    null,
    "not an object",
    42,
    {},
    { data: null },
    { data: {} },
    { data: { id: "evt_1" } }, // no attributes
    { data: { id: "evt_1", attributes: {} } }, // no type
    { data: { id: "", attributes: { type: "payment.paid" } } }, // empty id
    { data: { attributes: { type: "payment.paid" } } }, // no id
  ];

  for (const body of malformed) {
    assertEquals(
      parseEvent(body, NOW),
      null,
      `expected ${JSON.stringify(body)} to be rejected`,
    );
  }
});

Deno.test("a signed event with no recognisable resource grants nothing", () => {
  // Parses (it is a well-formed envelope) but carries no session binding.
  const event = parsed("checkout_session.payment.paid", {
    sessionId: undefined,
    userId: undefined,
  });
  const decision = run(event, null);

  assertEquals(decision.reason, "rejected_grant_unknown_payment");
  assertFalse(decision.processed, "should be flagged for a human to review");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

Deno.test("a paid event for a session we never created cannot grant", () => {
  // The signature is valid but no payment_records row matches — e.g. a
  // checkout created outside this app, or a replayed foreign session.
  const decision = run(parsed("checkout_session.payment.paid"), null);

  assertEquals(decision.reason, "rejected_grant_unknown_payment");
  assertGrantsNothing(decision);
});

Deno.test("a duplicate paid event is a no-op after the first handling", () => {
  const first = run(parsed("checkout_session.payment.paid"), pendingPayment());
  assertEquals(first.reason, "granted");

  // Replay the same purchase against the state the first one produced.
  const settled = pendingPayment({ status: "paid", updatedAt: NOW });
  const replay = run(
    parsed("checkout_session.payment.paid"),
    settled,
    activeEntitlement(),
  );

  assertEquals(replay.reason, "noop_grant_already_paid");
  assertEquals(replay.apply, null);
  assertGrantsNothing(replay);
});

Deno.test("a second distinct event id for one purchase does not grant twice", () => {
  // One purchase legitimately emits both checkout_session.payment.paid and
  // payment.paid, with different event ids — event-id dedupe alone would
  // let the second one through and grant again.
  const settled = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(
    parsed("payment.paid", { id: "evt_2" }),
    settled,
    activeEntitlement(),
  );

  assertEquals(decision.reason, "noop_grant_already_paid");
  assertGrantsNothing(decision);
});

// ───────────────── Ownership binding: one account only ───────────────────

Deno.test("metadata claiming another account cannot move Premium", () => {
  // The stored row says this checkout belongs to PARENT; the event claims
  // OTHER_PARENT. Neither account may be touched.
  const decision = run(
    parsed("checkout_session.payment.paid", { userId: OTHER_PARENT }),
    pendingPayment(),
  );

  assertEquals(decision.reason, "rejected_grant_owner_mismatch");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

Deno.test("the grant follows the stored owner, not the event metadata", () => {
  // With no metadata at all, the stored binding is the only source.
  const decision = run(
    parsed("checkout_session.payment.paid", { userId: undefined }),
    pendingPayment({ userId: OTHER_PARENT }),
  );

  assertEquals(decision.apply?.userId, OTHER_PARENT);
  assertEquals(decision.apply?.effect, "grant");
});

Deno.test("a mismatched failure cannot settle another account's payment", () => {
  const decision = run(
    parsed("payment.failed", { userId: OTHER_PARENT }),
    pendingPayment(),
  );

  assertEquals(decision.reason, "rejected_negative_owner_mismatch");
  assertEquals(decision.apply, null);
});

Deno.test("underpayment and wrong currency do not buy Premium", () => {
  const short = run(
    parsed("checkout_session.payment.paid", { amount: 100 }),
    pendingPayment(),
  );
  assertEquals(short.reason, "rejected_grant_amount_mismatch");
  assertGrantsNothing(short);

  const wrongCurrency = run(
    parsed("checkout_session.payment.paid", { currency: "USD" }),
    pendingPayment(),
  );
  assertEquals(wrongCurrency.reason, "rejected_grant_currency_mismatch");
  assertGrantsNothing(wrongCurrency);
});

// ─────────────────── Delayed and out-of-order delivery ───────────────────

Deno.test("a delayed expiry event cannot undo a payment that succeeded", () => {
  // Classic race: the session expiry fires late, after the paid event.
  const paid = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(
    parsed("checkout_session.expired", {
      id: "evt_late",
      createdAt: Math.floor(NOW.getTime() / 1000) - 600,
    }),
    paid,
    activeEntitlement(),
  );

  assertEquals(decision.reason, "ignored_negative_after_settled");
  assertEquals(decision.apply, null, "must not move paid → expired");
  assertGrantsNothing(decision);
});

Deno.test("a stale failure cannot overwrite a newer negative state", () => {
  const cancelled = pendingPayment({
    status: "cancelled",
    updatedAt: new Date("2026-08-21T11:59:00.000Z"),
  });
  const decision = run(parsed("payment.failed"), cancelled);

  assertEquals(decision.reason, "noop_negative_already_settled");
  assertEquals(decision.apply, null);
});

Deno.test("a negative event older than the stored row is ignored", () => {
  const payment = pendingPayment({
    updatedAt: new Date("2026-08-21T11:59:00.000Z"),
  });
  const decision = run(
    parsed("payment.failed", {
      createdAt: Math.floor(new Date("2026-08-21T11:00:00.000Z").getTime() / 1000),
    }),
    payment,
  );

  assertEquals(decision.reason, "ignored_negative_stale");
  assertEquals(decision.apply, null);
});

Deno.test("a signed paid event after a premature failure recovers the grant", () => {
  // PayMongo is authoritative that money moved, so a late authentic paid
  // event repairs a payment we had already written off.
  const failed = pendingPayment({ status: "failed" });
  const decision = run(parsed("checkout_session.payment.paid"), failed);

  assertEquals(decision.reason, "granted_after_recovery");
  assertEquals(decision.apply?.newStatus, "paid");
  assertEquals(decision.apply?.effect, "grant");
  assertEquals(decision.apply?.expectedStatus, "failed");
});

Deno.test("a paid event arriving after a refund cannot re-grant", () => {
  const refunded = pendingPayment({ status: "refunded", updatedAt: NOW });
  const decision = run(parsed("checkout_session.payment.paid"), refunded);

  assertEquals(decision.reason, "rejected_grant_after_refund");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

// ─────────────────────────── Refund / reversal ───────────────────────────

Deno.test("a refund revokes Premium and settles the payment", () => {
  const paid = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(
    parsed("payment.refunded", { id: "evt_refund" }),
    paid,
    activeEntitlement({ activatedAt: NOW }),
  );

  assertEquals(decision.reason, "revoked");
  assertEquals(decision.apply?.newStatus, "refunded");
  assertEquals(decision.apply?.effect, "revoke");
  assertEquals(decision.apply?.userId, PARENT);
});

Deno.test("replaying a refund is idempotent", () => {
  const refunded = pendingPayment({ status: "refunded", updatedAt: NOW });
  const revoked = activeEntitlement({ isPremium: false, updatedAt: NOW });
  const decision = run(
    parsed("payment.refunded", { id: "evt_refund_again" }),
    refunded,
    revoked,
  );

  assertEquals(decision.reason, "refund_settled_entitlement_already_inactive");
  assertEquals(decision.apply, null, "must not rewrite the settled row");
  assertGrantsNothing(decision);
});

Deno.test("refunding an old payment does not revoke a newer paid period", () => {
  // The parent was refunded for July, then bought August. The July refund
  // must not cancel Premium the August payment bought.
  const oldPayment = pendingPayment({
    status: "paid",
    updatedAt: new Date("2026-07-05T00:00:00.000Z"),
  });
  const newerPeriod = activeEntitlement({
    activatedAt: new Date("2026-08-15T00:00:00.000Z"),
  });

  const decision = run(parsed("payment.refunded"), oldPayment, newerPeriod);

  assertEquals(decision.reason, "refund_settled_newer_entitlement_kept");
  assertEquals(decision.apply?.newStatus, "refunded");
  assertGrantsNothing(decision);
});

Deno.test("a refund update without status reverses nothing", () => {
  const decision = run(
    parsed("payment.refund.updated"),
    pendingPayment({ status: "paid" }),
    activeEntitlement(),
  );
  assertEquals(decision.reason, "ignored_refund_not_succeeded");
  assertGrantsNothing(decision);
});

Deno.test("a pending or failed refund update reverses nothing", () => {
  const paid = pendingPayment({ status: "paid", updatedAt: NOW });

  for (const status of ["pending", "failed"]) {
    const decision = run(
      parsed("payment.refund.updated", { status }),
      paid,
      activeEntitlement({ activatedAt: NOW }),
    );
    assertEquals(decision.reason, "ignored_refund_not_succeeded");
    assertEquals(decision.apply, null);
    assertGrantsNothing(decision);
  }
});

Deno.test("a succeeded refund update reverses like a refund", () => {
  const paid = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(
    parsed("payment.refund.updated", { status: "succeeded" }),
    paid,
    activeEntitlement({ activatedAt: NOW }),
  );

  assertEquals(decision.reason, "revoked");
  assertEquals(decision.apply?.effect, "revoke");
  assertEquals(decision.apply?.newStatus, "refunded");
});

Deno.test("refunding a payment that never completed changes nothing", () => {
  const decision = run(parsed("payment.refunded"), pendingPayment());

  assertEquals(decision.reason, "ignored_refund_unpaid_payment");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

Deno.test("a refund for another account cannot revoke this one", () => {
  const paid = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(
    parsed("payment.refunded", { userId: OTHER_PARENT }),
    paid,
    activeEntitlement({ activatedAt: NOW }),
  );

  assertEquals(decision.reason, "rejected_refund_owner_mismatch");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

// ─────────────────────────── Grant repair path ───────────────────────────

Deno.test("a paid record with no entitlement is repaired", () => {
  const settled = pendingPayment({ status: "paid", updatedAt: NOW });
  const decision = run(parsed("checkout_session.payment.paid"), settled, null);

  assertEquals(decision.reason, "repaired_missing_entitlement");
  assert(decision.processed);
  assertEquals(decision.apply?.paymentId, "pay-row-1");
  assertEquals(decision.apply?.userId, PARENT);
  assertEquals(decision.apply?.expectedStatus, "paid");
  assertEquals(decision.apply?.newStatus, null);
  assertEquals(decision.apply?.effect, "grant");
});

Deno.test("a paid record with a stranded inactive entitlement is repaired", () => {
  const settled = pendingPayment({
    status: "paid",
    updatedAt: new Date("2026-08-21T11:30:00.000Z"),
  });
  const stranded = activeEntitlement({
    isPremium: false,
    updatedAt: new Date("2026-08-21T11:00:00.000Z"),
  });
  const decision = run(
    parsed("checkout_session.payment.paid"),
    settled,
    stranded,
  );

  assertEquals(decision.reason, "repaired_missing_entitlement");
  assertEquals(decision.apply?.newStatus, null);
  assertEquals(decision.apply?.effect, "grant");
});

Deno.test("a paid record is not repaired when a later revocation is newer", () => {
  const settled = pendingPayment({
    status: "paid",
    updatedAt: new Date("2026-08-21T11:00:00.000Z"),
  });
  const revokedLater = activeEntitlement({
    isPremium: false,
    activatedAt: new Date("2026-08-21T11:00:00.000Z"),
    updatedAt: new Date("2026-08-21T11:30:00.000Z"),
  });
  const decision = run(
    parsed("checkout_session.payment.paid"),
    settled,
    revokedLater,
  );

  assertEquals(decision.reason, "noop_grant_already_paid");
  assertEquals(decision.apply, null);
  assertGrantsNothing(decision);
});

// ───────────────────────────── Parsing detail ────────────────────────────

Deno.test("the session id is read from a payment resource's reference", () => {
  const body = {
    data: {
      id: "evt_payment",
      attributes: {
        type: "payment.paid",
        livemode: false,
        created_at: Math.floor(NOW.getTime() / 1000),
        data: {
          id: "pay_abc",
          attributes: {
            checkout_session_id: SESSION,
            amount: PRICE,
            currency: "PHP",
            metadata: { user_id: PARENT },
          },
        },
      },
    },
  };

  const event = parseEvent(body, NOW);
  assertEquals(event?.sessionId, SESSION);
  assertEquals(event?.paidAmount, PRICE);
  assertEquals(event?.outcome, "grant");
});

Deno.test("a missing created_at falls back to the receive time", () => {
  const body = {
    data: {
      id: "evt_no_ts",
      attributes: { type: "payment.paid", data: { id: SESSION } },
    },
  };

  assertEquals(parseEvent(body, NOW)?.occurredAt.getTime(), NOW.getTime());
});
