// Generates a warm, plain-language summary of a child's assessment result
// using Google Gemini (free tier). JWT-verified; the Gemini API key is read
// from Supabase Vault and never reaches the app. Data minimization: only
// skill levels, scores, and recommendation names are sent — never the
// child's name or any identifier.
//
// The app treats this as best-effort: on ANY failure here (missing key,
// Gemini error, quota, timeout) it falls back to the built-in rubric
// summary, so the parent always sees something.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const GEMINI_MODEL = 'gemini-2.5-flash';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Require a signed-in user (parent).
    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData, error: userError } =
      await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: 'unauthorized' }, 401);
    }

    const { data: apiKey } = await admin.rpc('get_vault_secret', {
      secret_name: 'GEMINI_API_KEY',
    });
    if (!apiKey) {
      return json({ error: 'summarizer not configured' }, 503);
    }

    const body = await req.json().catch(() => ({}));
    const areas = Array.isArray(body.areas) ? body.areas : [];
    const previousAreas = Array.isArray(body.previous_areas)
      ? body.previous_areas
      : [];
    const isProgress =
      body.mode === 'progress' && previousAreas.length > 0;
    const overallPct = typeof body.overall_pct === 'number'
      ? body.overall_pct
      : null;
    const supportLevel = typeof body.support_level === 'string'
      ? body.support_level
      : null;
    const recommendations = Array.isArray(body.recommendations)
      ? body.recommendations.slice(0, 8)
      : [];

    // Localize the summary to the parent's chosen language.
    const languageNames: Record<string, string> = {
      en: 'English',
      tl: 'Tagalog (Filipino)',
      ceb: 'Cebuano (Bisaya)',
    };
    const language = languageNames[body.language as string] ?? 'English';
    const langInstruction =
      `\nWrite your ENTIRE response in ${language}. Use warm, simple, `
      + 'everyday words a parent would use — not formal or technical.';

    const areaLines = areas
      .map((a: Record<string, unknown>) => `- ${a.name}: ${a.level}`)
      .join('\n');

    let prompt: string;
    if (isProgress) {
      // Pair each area's before → after level for a progress narrative.
      const prevByName = new Map(
        previousAreas.map((a: Record<string, unknown>) => [a.name, a.level]),
      );
      const changeLines = areas
        .map((a: Record<string, unknown>) =>
          `- ${a.name}: ${prevByName.get(a.name) ?? 'n/a'} -> ${a.level}`)
        .join('\n');
      prompt = [
        'You are writing a short, warm PROGRESS note for the parent of a ',
        'young child (ages 2-6) who just finished a follow-up set of ',
        'playful learning games, after practicing since their first round. ',
        'Using ONLY the before-and-after data below, write 2-3 encouraging ',
        'sentences about how their child has grown.',
        '',
        'Rules:',
        '- Address the parent, refer to "your child" (no names provided).',
        '- Celebrate specific areas that improved; if an area stayed the ',
        '  same, frame it warmly (steady, still a strength, keep practicing).',
        '- Warm and hopeful; never clinical.',
        '- Do NOT diagnose, label, or use medical terms (no "autism", ',
        '  "disorder", "deficit", "symptom", "delay").',
        '- Do NOT invent facts beyond the data. No markdown, just sentences.',
        '',
        'Skill areas (before -> after):',
        changeLines || '- (none)',
        recommendations.length
          ? `Suggested next activities: ${recommendations.join(', ')}`
          : '',
        langInstruction,
      ].join('\n');
    } else {
      prompt = [
        'You are writing a short, warm note for the parent of a young child ',
        '(ages 2-6) who just finished a set of playful learning games in an ',
        'app that supports early childhood development. Using ONLY the data ',
        'below, write 2-3 encouraging sentences in plain language.',
        '',
        'Rules:',
        '- Address the parent, refer to "your child" (no names are provided).',
        '- Lead with a strength, then gently note where practice will help.',
        '- Warm and hopeful; never clinical.',
        '- Do NOT diagnose, label, or use medical terms (no "autism", ',
        '  "disorder", "deficit", "symptom", "delay").',
        '- Do NOT invent facts beyond the data. No markdown, just sentences.',
        '',
        'Data:',
        `Overall game accuracy: ${overallPct == null ? 'n/a' : overallPct + '%'}`,
        `Support emphasis: ${supportLevel ?? 'n/a'}`,
        'Skill areas (level per area):',
        areaLines || '- (none)',
        recommendations.length
          ? `Suggested next activities: ${recommendations.join(', ')}`
          : '',
        langInstruction,
      ].join('\n');
    }

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 300,
            // gemini-2.5-flash spends output tokens on internal "thinking";
            // a 3-sentence summary needs none, so disable it (also faster).
            thinkingConfig: { thinkingBudget: 0 },
          },
          safetySettings: [
            { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
          ],
        }),
      },
    );

    if (!geminiResponse.ok) {
      const errBody = await geminiResponse.text();
      console.error('gemini error', geminiResponse.status, errBody.slice(0, 300));
      return json({ error: 'summarizer unavailable' }, 502);
    }

    const geminiData = await geminiResponse.json();
    const summary = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text
      ?.trim();
    if (!summary) {
      return json({ error: 'empty summary' }, 502);
    }

    return json({ summary });
  } catch (e) {
    console.error('summarize-assessment failed', e);
    return json({ error: 'internal error' }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
