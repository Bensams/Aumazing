// Text generation for the parent-facing summarizers, with a provider chain:
// Gemini (free tier) first, then Groq when Gemini is rate-limited, over quota
// or otherwise failing. When both fail the caller returns an error and the
// app writes its own on-device summary instead.
//
// Both API keys are read from Supabase Vault (GEMINI_API_KEY, GROQ_API_KEY)
// and never reach the app. A missing key simply skips that provider.
// deno-lint-ignore-file no-explicit-any

export type LlmProvider = 'gemini' | 'groq';

export interface LlmOptions {
  /** Ask for a JSON object reply (the prompt must describe its shape). */
  json?: boolean;
  /** Gemini-only structured output schema, used with [json]. */
  geminiSchema?: Record<string, unknown>;
  temperature?: number;
  /** Output budget for the visible answer. */
  maxTokens?: number;
  /**
   * Whether a reply is usable (e.g. parses as the expected JSON). A reply
   * that is not moves on to the next provider instead of failing.
   */
  accept?: (text: string) => boolean;
}

export interface LlmResult {
  text: string;
  provider: LlmProvider;
}

const GEMINI_MODEL = 'gemini-2.5-flash';
const GROQ_MODEL = 'openai/gpt-oss-120b';
// Each provider gets this long, so the whole chain stays under the app's
// 25 s summarizer timeout even when Gemini hangs before Groq answers.
const PROVIDER_TIMEOUT_MS = 10_000;

/** Reads a secret from Vault, falling back to a function env var. */
async function secret(admin: any, name: string): Promise<string | null> {
  try {
    const { data } = await admin.rpc('get_vault_secret', { secret_name: name });
    if (typeof data === 'string' && data.trim() !== '') return data.trim();
  } catch (e) {
    console.error(`vault read failed for ${name}`, e);
  }
  try {
    const env = Deno.env.get(name);
    return env && env.trim() !== '' ? env.trim() : null;
  } catch {
    return null; // no env access: Vault is the only source
  }
}

/**
 * Generates text with Gemini, falling back to Groq. Returns null when no
 * provider produced a usable answer (no keys, both limited, both failed).
 */
export async function generateWithFallback(
  admin: any,
  prompt: string,
  options: LlmOptions = {},
): Promise<LlmResult | null> {
  const accept = options.accept ?? (() => true);

  const geminiKey = await secret(admin, 'GEMINI_API_KEY');
  if (geminiKey) {
    const text = await callGemini(geminiKey, prompt, options);
    if (text && accept(text)) return { text, provider: 'gemini' };
    if (text) console.error('gemini reply rejected', text.slice(0, 200));
  }

  const groqKey = await secret(admin, 'GROQ_API_KEY');
  if (groqKey) {
    const text = await callGroq(groqKey, prompt, options);
    if (text && accept(text)) return { text, provider: 'groq' };
    if (text) console.error('groq reply rejected', text.slice(0, 200));
  }
  return null;
}

async function callGemini(
  apiKey: string,
  prompt: string,
  options: LlmOptions,
): Promise<string | null> {
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: options.temperature ?? 0.7,
            maxOutputTokens: options.maxTokens ?? 300,
            // A short summary needs no internal "thinking" (also faster).
            thinkingConfig: { thinkingBudget: 0 },
            ...(options.json
              ? {
                responseMimeType: 'application/json',
                ...(options.geminiSchema
                  ? { responseSchema: options.geminiSchema }
                  : {}),
              }
              : {}),
          },
          safetySettings: [
            { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
          ],
        }),
      },
    );
    if (!response.ok) {
      // 429 = rate limit / quota: the case the Groq fallback exists for.
      const body = await response.text();
      console.error('gemini error', response.status, body.slice(0, 300));
      return null;
    }
    const data = await response.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    return text ? text : null;
  } catch (e) {
    console.error('gemini request failed', e);
    return null;
  }
}

async function callGroq(
  apiKey: string,
  prompt: string,
  options: LlmOptions,
): Promise<string | null> {
  try {
    const response = await fetch(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
        body: JSON.stringify({
          model: GROQ_MODEL,
          messages: [{ role: 'user', content: prompt }],
          temperature: options.temperature ?? 0.7,
          top_p: 1,
          // Reasoning tokens share this budget with the answer, so leave
          // generous room on top of the visible reply.
          max_completion_tokens: Math.max(2048, (options.maxTokens ?? 300) * 3),
          reasoning_effort: 'medium',
          stream: false,
          ...(options.json ? { response_format: { type: 'json_object' } } : {}),
        }),
      },
    );
    if (!response.ok) {
      const body = await response.text();
      console.error('groq error', response.status, body.slice(0, 300));
      return null;
    }
    const data = await response.json();
    const text = data?.choices?.[0]?.message?.content?.trim();
    return text ? text : null;
  } catch (e) {
    console.error('groq request failed', e);
    return null;
  }
}

/** Parses a JSON object reply, tolerating stray text around the object. */
export function parseJsonObject(raw: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    const start = raw.indexOf('{');
    const end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      const parsed = JSON.parse(raw.slice(start, end + 1));
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
      return null;
    }
  }
}
