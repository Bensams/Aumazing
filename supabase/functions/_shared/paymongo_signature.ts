// paymongo_signature — HMAC verification for the Paymongo-Signature
// header. Split out of the webhook so it can be tested without booting
// the Deno.serve handler (AUM-168).

export async function hmacSha256Hex(
  secret: string,
  message: string,
): Promise<string> {
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

/// Constant-time compare, so a wrong signature cannot be discovered one
/// character at a time by timing the response.
export function timingSafeEqual(a: string, b: string): boolean {
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
export async function verifySignature(
  header: string | null,
  rawBody: string,
  livemode: boolean,
  secret: string,
): Promise<boolean> {
  if (!header) return false;
  const parts = new Map<string, string>();
  for (const part of header.split(",")) {
    const trimmed = part.trim();
    const eq = trimmed.indexOf("=");
    // A malformed segment must not throw and must not be readable as a
    // valid pair; skip it rather than destructuring blindly. (The old
    // `split("=")` turned "te=a=b" into ["te","a"], silently truncating.)
    if (eq <= 0) continue;
    const name = trimmed.slice(0, eq);
    if (!parts.has(name)) parts.set(name, trimmed.slice(eq + 1));
  }
  const timestamp = parts.get("t");
  const expected = livemode ? parts.get("li") : parts.get("te");
  if (!timestamp || !expected) return false;
  const computed = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  return timingSafeEqual(computed, expected);
}
