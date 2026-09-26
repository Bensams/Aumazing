// Writes the parent dashboard's OVERALL gameplay summary, plus questions the
// parent can bring to a therapist or practitioner. Google Gemini (free tier)
// writes it; when Gemini is rate-limited or failing, Groq writes it instead
// (see ../_shared/llm.ts). JWT-verified; both API keys are read from Supabase
// Vault and never reach the app. The reply names the provider that answered
// so the dashboard can say which one the parent is reading.
//
// Input covers the pre-assessment, the recommended activities (My Path,
// including how many tries each game took to reach Strength), the
// post-assessment and any later assessment cycle. Free practice is filtered
// out by the app before the request is built. Data minimization: only skill
// levels, accuracy percentages, counts and game names are sent — never the
// child's name or any identifier.
//
// The app treats this as best-effort: when both providers fail it writes
// the summary on the device instead and labels it as such.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { generateWithFallback, parseJsonObject } from '../_shared/llm.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type Area = { name?: unknown; level?: unknown };
type Assessment = {
  label?: unknown;
  accuracy_pct?: unknown;
  areas?: Area[];
};
type Activity = {
  name?: unknown;
  plays?: unknown;
  avg_accuracy_pct?: unknown;
  reached_strength?: unknown;
  tries?: unknown;
  last_level?: unknown;
};

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

    const body = await req.json().catch(() => ({}));
    const assessments: Assessment[] = Array.isArray(body.assessments)
      ? body.assessments.slice(0, 12)
      : [];
    const activities: Activity[] = Array.isArray(body.recommended_activities)
      ? body.recommended_activities.slice(0, 15)
      : [];
    const recommendedPlays = typeof body.recommended_plays === 'number'
      ? body.recommended_plays
      : 0;
    if (assessments.length === 0 && recommendedPlays === 0) {
      return json({ error: 'nothing to summarize' }, 400);
    }

    const languageNames: Record<string, string> = {
      en: 'English',
      tl: 'Tagalog (Filipino)',
      ceb: 'Cebuano (Bisaya)',
    };
    const language = languageNames[body.language as string] ?? 'English';

    const text = (v: unknown) => String(v ?? '').slice(0, 60);
    const assessmentLines = assessments.map((a) => {
      const areas = (Array.isArray(a.areas) ? a.areas : [])
        .map((x) => `${text(x.name)}: ${text(x.level)}`)
        .join('; ');
      return `- ${text(a.label)} — activity accuracy ${
        typeof a.accuracy_pct === 'number' ? a.accuracy_pct + '%' : 'n/a'
      }; ${areas || 'no area levels'}`;
    });
    const activityLines = activities.map((g) => {
      const tries = typeof g.tries === 'number' ? g.tries : 0;
      const outcome = g.reached_strength === true
        ? `reached Strength after ${tries} tr${tries === 1 ? 'y' : 'ies'}`
        : tries > 0
        ? `not yet Strength (${tries} tr${tries === 1 ? 'y' : 'ies'} so far, last level ${text(g.last_level) || 'n/a'})`
        : 'not played yet';
      const acc = typeof g.avg_accuracy_pct === 'number'
        ? `, average accuracy ${g.avg_accuracy_pct}%`
        : '';
      return `- ${text(g.name)}: ${outcome}${acc}`;
    });

    const prompt = [
      'You are helping the parent of a young child (ages 2-6) understand ',
      'the child\'s overall progress in a playful learning-games app. The ',
      'record below covers the assessments (in order: pre-assessment, then ',
      'recommended activities on "My Path", then post-assessment, possibly ',
      'repeated in later cycles). On My Path a game must reach the level ',
      '"Strength" before the next game unlocks, so the number of tries shows ',
      'how much practice each game needed.',
      '',
      'Write:',
      '1. "summary": 4-6 warm, plain-language sentences about the child\'s ',
      '   overall journey — strengths first, then growth across cycles, then ',
      '   what is still being practised and how many tries games needed.',
      '2. "questions": 3-5 short, specific questions the parent could ask ',
      '   the child\'s therapist or practitioner at the next visit, grounded ',
      '   in this record (for example about areas still growing, or a game ',
      '   that took many tries).',
      '',
      'Rules:',
      '- Address the parent; refer to "your child" (no names are provided).',
      '- Warm and hopeful; never clinical.',
      '- Do NOT diagnose, label, or use medical terms (no "autism", ',
      '  "disorder", "deficit", "symptom", "delay").',
      '- Do NOT invent facts beyond the record. No markdown.',
      `- Write the ENTIRE response (summary and questions) in ${language}, `,
      '  using simple everyday words.',
      '- Reply with ONLY a JSON object of the form ',
      '  {"summary": "...", "questions": ["...", "..."]}.',
      '',
      'Assessments (oldest first):',
      assessmentLines.join('\n') || '- (none yet)',
      '',
      `Recommended activities (My Path), ${recommendedPlays} plays in total:`,
      activityLines.join('\n') || '- (none yet)',
    ].join('\n');

    const result = await generateWithFallback(admin, prompt, {
      json: true,
      temperature: 0.6,
      maxTokens: 900,
      geminiSchema: {
        type: 'OBJECT',
        properties: {
          summary: { type: 'STRING' },
          questions: { type: 'ARRAY', items: { type: 'STRING' } },
        },
        required: ['summary', 'questions'],
      },
      accept: (text) => {
        const reply = parseJsonObject(text);
        return typeof reply?.summary === 'string' &&
          reply.summary.trim() !== '';
      },
    });
    if (!result) {
      return json({ error: 'summarizer unavailable' }, 502);
    }

    // Accepted above, so this parses.
    const parsed = parseJsonObject(result.text)!;
    const summary = typeof parsed.summary === 'string'
      ? parsed.summary.trim()
      : '';
    const questions = Array.isArray(parsed.questions)
      ? parsed.questions
        .filter((q): q is string => typeof q === 'string' && q.trim() !== '')
        .map((q) => q.trim())
        .slice(0, 5)
      : [];
    if (!summary) {
      return json({ error: 'empty summary' }, 502);
    }

    return json({ summary, questions, provider: result.provider });
  } catch (e) {
    console.error('summarize-gameplay failed', e);
    return json({ error: 'internal error' }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
