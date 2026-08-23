// payment_outcomes — the decision layer for PayMongo payment outcomes
// (AUM-168). Pure functions only: no network, no database, no clock. The
// webhook shell reads the stored state, calls `decide`, and applies the
// single effect it returns, so every outcome rule is directly testable.
//
// Three invariants this module exists to guarantee:
//
//   1. Premium is granted only for an authentic paid event that matches a
//      checkout WE created, for the account that created it.
//   2. Failed / cancelled / expired / timed-out outcomes never grant, and
//      never disturb an entitlement.
//   3. Duplicates, replays, delayed and out-of-order deliveries are
//      no-ops rather than corrections — a stale event can never overwrite
//      a newer valid state.
//
// Idempotency does NOT rest on the event id alone. A single purchase can
// legitimately arrive as two different event ids (`checkout_session
// .payment.paid` and `payment.paid`), so a second grant would re-apply
// the entitlement. Instead every effect is keyed on a *state transition*
// of the stored payment record: a grant only applies to a record that is
// not already paid. Event-id dedupe stays as the cheap first line of
// defence.
//
// A decision produces at most ONE `apply` value, deliberately: the
// payment transition and the entitlement effect are handed to the
// database together (`apply_payment_outcome`) so they commit or roll back
// as one transaction. There is no shape in this module that can express
// "move the payment now, grant later".
//
// Subscription lifecycle is outside this payment-outcome decision layer.
// A grant writes `is_premium`, `source` and `activated_at`; the period
// column is left to that ticket.

/// How a PayMongo event type maps onto our payment lifecycle.
export type OutcomeKind = "grant" | "negative" | "reversal" | "unknown";

/// Lifecycle of a `payment_records` row. `pending` is written by
/// create-checkout; every other value is written only by the webhook.
export type PaymentStatus =
  | "pending"
  | "paid"
  | "failed"
  | "cancelled"
  | "expired"
  | "refunded";

/// What a decision does to the entitlement row, if anything.
export type EntitlementEffect = "none" | "grant" | "revoke";

/// Terminal states — a payment that reached one of these is never moved
/// back to `pending`, and negative events against it are ignored.
const NEGATIVE_TERMINAL: readonly PaymentStatus[] = [
  "failed",
  "cancelled",
  "expired",
];

/// Event type → outcome. Anything absent is `unknown`: acknowledged and
/// logged, but it can never move money or entitlements.
const EVENT_OUTCOMES: Readonly<Record<string, OutcomeKind>> = {
  // Authentic payment completed.
  "checkout_session.payment.paid": "grant",
  "payment.paid": "grant",
  // The parent did not pay: declined card, abandoned checkout, or the
  // hosted session timed out. All of these are "no Premium".
  "payment.failed": "negative",
  "checkout_session.payment.failed": "negative",
  "checkout_session.expired": "negative",
  "checkout_session.cancelled": "negative",
  "payment.cancelled": "negative",
  "payment.expired": "negative",
  // Money given back after a grant.
  "payment.refunded": "reversal",
  "payment.refund.updated": "reversal",
};

/// The payment status a negative event settles the record at, so the
/// parent-facing history distinguishes "card declined" from "gave up".
const NEGATIVE_STATUS: Readonly<Record<string, PaymentStatus>> = {
  "payment.failed": "failed",
  "checkout_session.payment.failed": "failed",
  "checkout_session.expired": "expired",
  "payment.expired": "expired",
  "checkout_session.cancelled": "cancelled",
  "payment.cancelled": "cancelled",
};

export function classifyEventType(eventType: string | undefined): OutcomeKind {
  if (!eventType) return "unknown";
  return EVENT_OUTCOMES[eventType] ?? "unknown";
}

/// The fields we trust off a PayMongo event, once it is shaped correctly.
export interface ParsedEvent {
  eventId: string;
  eventType: string;
  livemode: boolean;
  outcome: OutcomeKind;
  /// When PayMongo says the event happened — the ordering key for
  /// delayed and out-of-order deliveries.
  occurredAt: Date;
  /// Checkout session this event belongs to, when the resource carries it.
  sessionId?: string;
  /// The account PayMongo believes owns this, from checkout metadata.
  /// A *claim*, never trusted on its own — it must match the stored row.
  claimedUserId?: string;
  /// Amount actually collected, in centavos, when the resource reports it.
  paidAmount?: number;
  paidCurrency?: string;
  /// For `payment.refund.updated`: refunds are only honoured once they
  /// have actually succeeded.
  refundSucceeded: boolean;
}

/// The stored payment we are reconciling against — the record written by
/// create-checkout, which is what binds a PayMongo session to an account.
export interface StoredPayment {
  id: string;
  userId: string;
  checkoutSessionId: string | null;
  amount: number | null;
  currency: string | null;
  status: PaymentStatus;
  /// Last time we wrote this row; used as the staleness floor.
  updatedAt: Date | null;
}

export interface StoredEntitlement {
  userId: string;
  isPremium: boolean;
  activatedAt: Date | null;
  updatedAt: Date | null;
}

/// Everything the shell loaded for this event.
export interface DecisionContext {
  event: ParsedEvent;
  payment: StoredPayment | null;
  entitlement: StoredEntitlement | null;
  now: Date;
}

/// The one write a decision authorises, handed to the database as a
/// single atomic call. `expectedStatus` is the status the decision was
/// reasoned about; the database re-checks it under a row lock and
/// refuses to apply anything if the row has moved in the meantime, which
/// is what makes two concurrent deliveries safe.
export interface OutcomeApplication {
  paymentId: string;
  /// The owner the effect belongs to. Re-validated against the locked
  /// row, so a lookup that raced with an ownership change cannot land.
  userId: string;
  expectedStatus: PaymentStatus;
  /// `null` leaves the payment status alone — an entitlement-only
  /// effect, used by the repair path below.
  newStatus: PaymentStatus | null;
  effect: EntitlementEffect;
  /// Entitlement provenance, kept split so a sandbox grant is never
  /// mistaken for a live one in the admin views.
  source: string;
  at: Date;
}

/// What the shell should do. `apply: null` is a safe acknowledgement:
/// the event is recorded, nothing else changes.
export interface Decision {
  /// Machine-readable reason, asserted on in tests and logged in prod.
  reason: string;
  /// Whether the event was understood and fully settled. `false` marks
  /// deliveries a human may need to look at (unmatched references).
  processed: boolean;
  apply: OutcomeApplication | null;
}

function noop(reason: string, processed = true): Decision {
  return { reason, processed, apply: null };
}

function asDate(value: unknown): Date | null {
  if (value == null) return null;
  // PayMongo timestamps are unix seconds; Supabase returns ISO strings.
  if (typeof value === "number") {
    const d = new Date(value * 1000);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof value === "string") {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  return null;
}

/// Extracts the event we can reason about, or `null` when the payload is
/// malformed. Returning `null` means the shell writes NOTHING — a
/// garbage body must not be able to create rows.
export function parseEvent(
  body: unknown,
  fallbackNow: Date,
): ParsedEvent | null {
  if (typeof body !== "object" || body === null) return null;
  // deno-lint-ignore no-explicit-any
  const data = (body as any).data;
  if (typeof data !== "object" || data === null) return null;

  const eventId = data.id;
  const attributes = data.attributes;
  if (typeof eventId !== "string" || eventId.length === 0) return null;
  if (typeof attributes !== "object" || attributes === null) return null;

  const eventType = attributes.type;
  if (typeof eventType !== "string" || eventType.length === 0) return null;

  const resource = attributes.data;
  const resourceAttributes =
    typeof resource === "object" && resource !== null
      ? resource.attributes
      : null;

  // The checkout session id can arrive as the resource itself (checkout
  // events) or as a reference on the payment (payment events).
  let sessionId: string | undefined;
  const resourceId = typeof resource?.id === "string" ? resource.id : undefined;
  if (resourceId?.startsWith("cs_")) {
    sessionId = resourceId;
  }
  const referenced = resourceAttributes?.checkout_session_id;
  if (typeof referenced === "string" && referenced.length > 0) {
    sessionId = referenced;
  }

  const claimed = resourceAttributes?.metadata?.user_id;
  const claimedUserId =
    typeof claimed === "string" && claimed.length > 0 ? claimed : undefined;

  // A checkout session reports what was actually collected under
  // `payments[]`; a payment resource reports it directly.
  let paidAmount: number | undefined;
  let paidCurrency: string | undefined;
  const payments = resourceAttributes?.payments;
  const firstPayment = Array.isArray(payments) ? payments[0]?.attributes : null;
  const amountSource = firstPayment ?? resourceAttributes;
  if (typeof amountSource?.amount === "number") {
    paidAmount = amountSource.amount;
  }
  if (typeof amountSource?.currency === "string") {
    paidCurrency = amountSource.currency;
  }

  // A refund is only real once it has succeeded; `payment.refund.updated`
  // also fires while the refund is still pending or after it failed.
  const refundStatus = resourceAttributes?.status;
  const refundSucceeded =
    eventType === "payment.refunded" ||
    refundStatus === "succeeded";

  return {
    eventId,
    eventType,
    livemode: attributes.livemode === true,
    outcome: classifyEventType(eventType),
    occurredAt: asDate(attributes.created_at) ?? fallbackNow,
    sessionId,
    claimedUserId,
    paidAmount,
    paidCurrency,
    refundSucceeded,
  };
}

/// Entitlement `source`, kept split so a sandbox grant is never mistaken
/// for a live one in the admin views.
export function entitlementSource(livemode: boolean): string {
  return livemode ? "paymongo" : "paymongo_test";
}

/// True when the event is older than the state already stored — a
/// delayed or replayed delivery that must not overwrite newer truth.
function isStale(event: ParsedEvent, storedAt: Date | null): boolean {
  if (!storedAt) return false;
  return event.occurredAt.getTime() < storedAt.getTime();
}

/// The single decision point for every payment outcome.
export function decide(context: DecisionContext): Decision {
  const { event, payment, entitlement, now } = context;

  switch (event.outcome) {
    case "unknown":
      // Acknowledged so PayMongo stops retrying; nothing else happens.
      return noop(`ignored_unknown_event:${event.eventType}`);

    case "grant":
      return decideGrant(event, payment, entitlement, now);

    case "negative":
      return decideNegative(event, payment, now);

    case "reversal":
      return decideReversal(event, payment, entitlement, now);
  }
}

/// A payment that says `paid` but has no Premium behind it is the shape a
/// half-applied grant would leave. `apply_payment_outcome` commits both
/// halves in one transaction so this should be unreachable for anything it
/// wrote, but rows written before that function existed — or a period
/// removed by hand — would otherwise be stranded forever, because the
/// ordinary grant path sees `paid` and stops.
///
/// The guard against undoing newer truth is the same ordering rule the
/// refund path uses: if something wrote the entitlement row *after* this
/// payment settled (a refund, an admin revocation), that is the later
/// decision and it stands.
function needsGrantRepair(
  entitlement: StoredEntitlement | null,
  payment: StoredPayment,
): boolean {
  if (entitlement?.isPremium === true) return false;
  if (!entitlement) return true;
  if (
    entitlement.updatedAt != null &&
    payment.updatedAt != null &&
    entitlement.updatedAt.getTime() > payment.updatedAt.getTime()
  ) {
    return false;
  }
  return true;
}

function decideGrant(
  event: ParsedEvent,
  payment: StoredPayment | null,
  entitlement: StoredEntitlement | null,
  now: Date,
): Decision {
  // No stored checkout means we never started this payment. Granting on
  // an unknown reference would let any session PayMongo ever signed —
  // including one created outside this app — mint Premium.
  if (!payment) {
    return noop("rejected_grant_unknown_payment", false);
  }

  // Ownership: the metadata claim must agree with the row create-checkout
  // wrote. A mismatch means the event cannot be attributed safely, so it
  // must not touch either account.
  if (event.claimedUserId && event.claimedUserId !== payment.userId) {
    return noop("rejected_grant_owner_mismatch", false);
  }

  // Underpayment: honour only what we actually asked for. A session
  // settled for less than the Premium price is not a Premium purchase.
  if (
    payment.amount != null &&
    event.paidAmount != null &&
    event.paidAmount < payment.amount
  ) {
    return noop("rejected_grant_amount_mismatch", false);
  }
  if (
    payment.currency &&
    event.paidCurrency &&
    event.paidCurrency.toUpperCase() !== payment.currency.toUpperCase()
  ) {
    return noop("rejected_grant_currency_mismatch", false);
  }

  const source = entitlementSource(event.livemode);

  // Already paid: this is a redelivery, or the second of the two event
  // types one purchase produces. Applying again would re-stamp the
  // entitlement — unless the entitlement is genuinely missing, which is
  // the recovery case above.
  if (payment.status === "paid") {
    if (needsGrantRepair(entitlement, payment)) {
      return {
        reason: "repaired_missing_entitlement",
        processed: true,
        apply: {
          paymentId: payment.id,
          userId: payment.userId,
          expectedStatus: "paid",
          newStatus: null, // already settled; only the grant is missing
          effect: "grant",
          source,
          at: now,
        },
      };
    }
    return noop("noop_grant_already_paid");
  }

  // Refunded is terminal. A paid event arriving after the money went back
  // must never re-grant.
  if (payment.status === "refunded") {
    return noop("rejected_grant_after_refund", false);
  }

  // A negative terminal (failed/cancelled/expired) followed by a signed
  // paid event means our earlier inference lost the race — PayMongo is
  // authoritative that money moved, so recover and grant.
  const recovering = NEGATIVE_TERMINAL.includes(payment.status);

  return {
    reason: recovering ? "granted_after_recovery" : "granted",
    processed: true,
    apply: {
      paymentId: payment.id,
      userId: payment.userId,
      expectedStatus: payment.status,
      newStatus: "paid",
      effect: "grant",
      source,
      at: now,
    },
  };
}

function decideNegative(
  event: ParsedEvent,
  payment: StoredPayment | null,
  now: Date,
): Decision {
  // A failure we cannot attribute changes nothing — and, critically, a
  // negative outcome NEVER reads or writes an entitlement.
  if (!payment) {
    return noop("ignored_negative_unknown_payment", false);
  }
  if (event.claimedUserId && event.claimedUserId !== payment.userId) {
    return noop("rejected_negative_owner_mismatch", false);
  }

  // The out-of-order case that matters: a delayed "expired"/"failed"
  // arriving after the payment actually succeeded must not undo it.
  if (payment.status === "paid" || payment.status === "refunded") {
    return noop("ignored_negative_after_settled");
  }
  if (NEGATIVE_TERMINAL.includes(payment.status)) {
    return noop("noop_negative_already_settled");
  }
  if (isStale(event, payment.updatedAt)) {
    return noop("ignored_negative_stale");
  }

  const status = NEGATIVE_STATUS[event.eventType] ?? "failed";
  return {
    reason: `settled_${status}`,
    processed: true,
    apply: {
      paymentId: payment.id,
      userId: payment.userId,
      expectedStatus: payment.status,
      newStatus: status,
      // Deliberately "none": no failure path may touch Premium.
      effect: "none",
      source: entitlementSource(event.livemode),
      at: now,
    },
  };
}

function decideReversal(
  event: ParsedEvent,
  payment: StoredPayment | null,
  entitlement: StoredEntitlement | null,
  now: Date,
): Decision {
  // `payment.refund.updated` fires for pending and failed refunds too;
  // only a succeeded refund reverses anything.
  if (!event.refundSucceeded) {
    return noop("ignored_refund_not_succeeded");
  }
  if (!payment) {
    return noop("ignored_refund_unknown_payment", false);
  }
  if (event.claimedUserId && event.claimedUserId !== payment.userId) {
    return noop("rejected_refund_owner_mismatch", false);
  }
  // Refunding something that never completed is a no-op, not a downgrade.
  if (payment.status !== "paid" && payment.status !== "refunded") {
    return noop("ignored_refund_unpaid_payment");
  }

  const source = entitlementSource(event.livemode);
  // Already settled as refunded — keep the original refund timestamp.
  const newStatus: PaymentStatus | null = payment.status === "refunded"
    ? null
    : "refunded";

  // The out-of-order guard for entitlements: if the running Premium
  // period was activated *after* this payment was settled, it was bought
  // by a newer payment. Refunding the older one must not revoke it.
  const entitlementIsNewer = entitlement?.isPremium === true &&
    entitlement.activatedAt != null &&
    payment.updatedAt != null &&
    entitlement.activatedAt.getTime() > payment.updatedAt.getTime();

  // Already revoked, or belonging to a newer payment: settle the payment
  // row (if it still needs settling) and leave Premium alone.
  if (entitlementIsNewer || !entitlement || entitlement.isPremium === false) {
    const reason = entitlementIsNewer
      ? "refund_settled_newer_entitlement_kept"
      : "refund_settled_entitlement_already_inactive";
    if (newStatus === null) {
      return noop(reason);
    }
    return {
      reason,
      processed: true,
      apply: {
        paymentId: payment.id,
        userId: payment.userId,
        expectedStatus: payment.status,
        newStatus,
        effect: "none",
        source,
        at: now,
      },
    };
  }

  return {
    reason: "revoked",
    processed: true,
    apply: {
      paymentId: payment.id,
      userId: payment.userId,
      expectedStatus: payment.status,
      newStatus,
      effect: "revoke",
      source,
      at: now,
    },
  };
}
