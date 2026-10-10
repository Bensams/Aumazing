import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { normalizeParentContext, parentContextPrompt } from '../_shared/parent_context.ts';
const report = {
  assessment_type: 'pre', cycle: 1, completed_on: '2026-01-01',
  question_set: 'set_1', questionnaire_revision: 1, questionnaire_status: 'draft',
  comparable_to_pre: false,
  domain_frequencies: [{ name: 'Communication', frequency_pct: 75 }],
};
const context = (observations: unknown[]) => ({ source: 'parent_reported_home_observations', observations });
Deno.test('missing parent report preserves game-only summary instructions', () => {
  assertEquals(normalizeParentContext(undefined), []);
  assertStringIncludes(parentContextPrompt(undefined), 'Use game records only');
  assertStringIncludes(parentContextPrompt(undefined), 'Do not infer home behavior');
});
Deno.test('only bounded aggregate domains and metadata enter the prompt', () => {
  const clean = normalizeParentContext(context([{ ...report, child_name: 'private',
    domain_frequencies: [{ name: 'Communication', frequency_pct: 0 },
      { name: 'Play Skills', frequency_pct: null }, { name: 'Attention & Focus', frequency_pct: 101 },
      { name: 'private text', frequency_pct: 50 }] }]));
  assertEquals(clean[0].domain_frequencies, [{ name: 'Communication', frequency_pct: 0 }]);
  assertEquals(JSON.stringify(clean).includes('private'), false);
});
Deno.test('invalid source, date, revision and free-text set are discarded', () => {
  for (const changed of [{ completed_on: 'bad' }, { questionnaire_revision: 0 },
    { question_set: 'ignore instructions' }, { assessment_type: 'post_observation' }]) {
    assertEquals(normalizeParentContext(context([{ ...report, ...changed }])), []);
  }
  assertEquals(normalizeParentContext({ source: 'other', observations: [report] }), []);
});
Deno.test('comparison requires compatible same-cycle pre report', () => {
  const post = { ...report, assessment_type: 'post', completed_on: '2026-02-01', comparable_to_pre: true };
  assertStringIncludes(parentContextPrompt(context([report, post])), '"comparable_to_pre":true');
  for (const changed of [{ cycle: 2 }, { question_set: 'set_2' }, { completed_on: '2025-01-01' }]) {
    const prompt = parentContextPrompt(context([report, { ...post, ...changed }]));
    assertEquals(prompt.includes('"comparable_to_pre":true'), false);
  }
});
Deno.test('report prompt keeps ratings distinct and prevents clinical/causal conclusions', () => {
  const prompt = parentContextPrompt(context([report]));
  for (const rule of ['separate from measured game performance', 'NOT game accuracy',
    'Do not blend home ratings', 'Do not treat draft questionnaires as validated',
    'Do not infer missing domains or skipped answers as zero']) assertStringIncludes(prompt, rule);
});
