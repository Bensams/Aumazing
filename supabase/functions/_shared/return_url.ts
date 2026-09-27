// Where PayMongo sends a parent after web checkout (create-checkout).

// The web app's return address, or null when absent or not allowed. Only
// known origins are accepted, so the checkout cannot be used to send a parent
// to someone else's site after paying.
export function allowedReturnUrl(
  raw: unknown,
  allowedOrigins: string[],
): URL | null {
  if (typeof raw !== "string" || raw.length > 2048) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
  if (local ? url.protocol !== "http:" && url.protocol !== "https:"
            : url.protocol !== "https:") {
    return null;
  }
  if (!local && !allowedOrigins.includes(url.origin)) return null;
  url.hash = "";
  url.searchParams.delete("payment");
  return url;
}

export function withOutcome(base: URL, outcome: "success" | "cancelled"): string {
  const url = new URL(base.href);
  url.searchParams.set("payment", outcome);
  return url.href;
}
