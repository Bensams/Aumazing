const domains = new Set([
  'Communication', 'Play Skills', 'Social Interaction', 'Attention & Focus',
]);

type HomeReport = {
  assessment_type: 'pre' | 'post';
  cycle: number | null;
  completed_on: string;
  question_set: string;
  questionnaire_revision: number;
  questionnaire_status: 'draft' | 'validated';
  comparable_to_pre: boolean;
  domain_frequencies: { name: string; frequency_pct: number }[];
};

/** Keeps only bounded aggregate observations; no identifiers or free text. */
export function normalizeParentContext(raw: unknown): HomeReport[] {
  if (!raw || typeof raw !== 'object') return [];
  const context = raw as Record<string, unknown>;
  if (context.source !== 'parent_reported_home_observations' ||
      !Array.isArray(context.observations)) return [];
  const result: HomeReport[] = [];
  for (const value of context.observations.slice(-12)) {
    if (!value || typeof value !== 'object') continue;
    const item = value as Record<string, unknown>;
    if ((item.assessment_type !== 'pre' && item.assessment_type !== 'post') ||
        typeof item.completed_on !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}$/.test(item.completed_on) ||
        !Number.isFinite(Date.parse(item.completed_on)) ||
        typeof item.question_set !== 'string' ||
        !/^set_[1-9]\d{0,2}$/.test(item.question_set) ||
        typeof item.questionnaire_revision !== 'number' ||
        !Number.isInteger(item.questionnaire_revision) || item.questionnaire_revision < 1 ||
        !Array.isArray(item.domain_frequencies)) continue;
    const frequencies = new Map<string, number>();
    for (const entry of item.domain_frequencies.slice(0, 4)) {
      if (!entry || typeof entry !== 'object') continue;
      const field = entry as Record<string, unknown>;
      if (typeof field.name === 'string' && domains.has(field.name) &&
          typeof field.frequency_pct === 'number' && Number.isFinite(field.frequency_pct) &&
          field.frequency_pct >= 0 && field.frequency_pct <= 100) {
        frequencies.set(field.name, field.frequency_pct);
      }
    }
    if (frequencies.size === 0) continue;
    result.push({
      assessment_type: item.assessment_type,
      cycle: typeof item.cycle === 'number' && Number.isInteger(item.cycle) && item.cycle > 0
        ? item.cycle : null,
      completed_on: item.completed_on,
      question_set: item.question_set,
      questionnaire_revision: item.questionnaire_revision,
      questionnaire_status: item.questionnaire_status === 'validated' ? 'validated' : 'draft',
      comparable_to_pre: item.comparable_to_pre === true,
      domain_frequencies: [...frequencies].map(([name, frequency_pct]) => ({ name, frequency_pct })),
    });
  }
  return result;
}

export function parentContextPrompt(raw: unknown): string {
  const reports = normalizeParentContext(raw);
  if (reports.length === 0) {
    return 'No parent-reported home observations are available. Use game records only. '
      + 'Do not infer home behavior or why the questionnaire is absent.';
  }
  const lines = reports.map((report, index) => {
    const earlier = reports.slice(0, index).filter((other) => other.assessment_type === 'pre' &&
      other.cycle !== null && other.cycle === report.cycle &&
      other.completed_on <= report.completed_on);
    const pre = earlier.at(-1);
    const comparable = report.assessment_type === 'post' && report.comparable_to_pre &&
      pre !== undefined && pre.question_set === report.question_set;
    return JSON.stringify({ ...report, comparable_to_pre: comparable });
  });
  return [
    'Parent-reported home observations (separate from measured game performance):',
    ...lines,
    'Use at most one or two clearly attributed sentences about these home reports.',
    'frequency_pct is mean reported frequency on a 0–100 scale, NOT game accuracy, ability or a clinical score.',
    'Always say the parent reported/noticed the home behavior. Keep the source and date/cycle clear.',
    'Do not blend home ratings with game scores, change recommendations, diagnose, or claim the games caused changes.',
    'Compare home ratings only within the same cycle when comparable_to_pre is true. Otherwise describe each report separately, without improvement/decline claims.',
    'Do not treat draft questionnaires as validated measures. Do not infer missing domains or skipped answers as zero.',
    'Differences between game performance and home reports are different observations, not proof that either source is wrong.',
  ].join('\n');
}
