// Run with: deno test supabase/functions/tests/
import { assertEquals } from 'jsr:@std/assert@1';
import { generateWithFallback, parseJsonObject } from '../_shared/llm.ts';

/** A stand-in admin client whose Vault holds [secrets]. */
function adminWith(secrets: Record<string, string>) {
  return {
    rpc: (_fn: string, args: { secret_name: string }) =>
      Promise.resolve({ data: secrets[args.secret_name] ?? null }),
  };
}

const geminiOk = (text: string) =>
  new Response(
    JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }),
    { status: 200 },
  );
const groqOk = (text: string) =>
  new Response(
    JSON.stringify({ choices: [{ message: { content: text } }] }),
    { status: 200 },
  );

/** Replaces fetch for one test, recording which hosts were called. */
async function withFetch(
  handler: (url: string) => Response,
  body: (calls: string[]) => Promise<void>,
) {
  const original = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    calls.push(new URL(url).host);
    return Promise.resolve(handler(url));
  }) as typeof fetch;
  try {
    await body(calls);
  } finally {
    globalThis.fetch = original;
  }
}

const keys = { GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q' };

Deno.test('Gemini answers first when it can', async () => {
  await withFetch(
    (url) => url.includes('googleapis') ? geminiOk('from gemini') : groqOk('x'),
    async (calls) => {
      const result = await generateWithFallback(adminWith(keys), 'p');
      assertEquals(result, { text: 'from gemini', provider: 'gemini' });
      assertEquals(calls, ['generativelanguage.googleapis.com']);
    },
  );
});

Deno.test('a rate-limited Gemini falls back to Groq', async () => {
  await withFetch(
    (url) =>
      url.includes('googleapis')
        ? new Response('quota', { status: 429 })
        : groqOk('from groq'),
    async () => {
      const result = await generateWithFallback(adminWith(keys), 'p');
      assertEquals(result, { text: 'from groq', provider: 'groq' });
    },
  );
});

Deno.test('a Gemini reply that fails validation falls back to Groq', async () => {
  await withFetch(
    (url) =>
      url.includes('googleapis')
        ? geminiOk('not json')
        : groqOk('{"summary":"ok","questions":[]}'),
    async () => {
      const result = await generateWithFallback(adminWith(keys), 'p', {
        json: true,
        accept: (t) => parseJsonObject(t) !== null,
      });
      assertEquals(result?.provider, 'groq');
    },
  );
});

Deno.test('both failing yields null so the app summarizes on device', async () => {
  await withFetch(
    () => new Response('down', { status: 503 }),
    async () => {
      assertEquals(await generateWithFallback(adminWith(keys), 'p'), null);
    },
  );
});

Deno.test('a missing Groq key skips Groq', async () => {
  await withFetch(
    () => new Response('quota', { status: 429 }),
    async (calls) => {
      const result = await generateWithFallback(
        adminWith({ GEMINI_API_KEY: 'g' }),
        'p',
      );
      assertEquals(result, null);
      assertEquals(calls, ['generativelanguage.googleapis.com']);
    },
  );
});

Deno.test('parseJsonObject tolerates text around the object', () => {
  assertEquals(parseJsonObject('Sure! {"summary":"a"} done'), { summary: 'a' });
  assertEquals(parseJsonObject('no object here'), null);
});
