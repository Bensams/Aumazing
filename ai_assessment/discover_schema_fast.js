const https = require('https');

const BASE_URL = 'https://lzvvjlcfoyczikaszrbp.supabase.co/rest/v1';
const API_KEY = 'sb_publishable_LmDmXen9C_J8G_SDMi-LCA_sD23uwZv';

const TABLES = [
  'children',
  'sensory_profiles',
  'module_paths',
  'module_path_items',
  'game_sessions',
  'game_rounds',
  'session_events',
  'assessment_runs',
  'assessment_results',
  'assessment_comparisons',
  'caregiver_questionnaires',
  'module_recommendations',
  'learning_modules',
];

const COMMON_COLUMNS = [
  'id', 'created_at', 'updated_at', 'deleted_at',
  'user_id', 'child_id', 'parent_id', 'caregiver_id',
  'name', 'title', 'description', 'label', 'slug', 'type', 'status',
  'first_name', 'last_name', 'display_name', 'nickname', 'email',
  'date_of_birth', 'dob', 'birth_date', 'age', 'age_months',
  'gender', 'diagnosis', 'notes', 'metadata',
  'session_id', 'game_id', 'round_id', 'module_id', 'path_id',
  'assessment_id', 'assessment_run_id', 'run_id', 'result_id',
  'questionnaire_id', 'profile_id', 'event_id', 'comparison_id',
  'score', 'total_score', 'max_score', 'percentage', 'rating', 'level',
  'start_time', 'end_time', 'started_at', 'ended_at', 'completed_at',
  'duration', 'duration_ms', 'duration_seconds',
  'is_active', 'is_completed', 'is_deleted', 'active', 'completed',
  'data', 'config', 'settings', 'options', 'payload',
  'event_type', 'event_data', 'event_name', 'action',
  'game_type', 'game_name', 'round_number', 'round_type',
  'module_name', 'module_type', 'module_path_id',
  'difficulty', 'difficulty_level',
  'response', 'answer', 'question', 'question_id',
  'visual', 'auditory', 'tactile', 'vestibular', 'proprioceptive',
  'oral', 'olfactory', 'interoceptive',
  'sensory_type', 'sensory_category', 'sensory_score',
  'category', 'subcategory', 'domain', 'area',
  'recommendation', 'recommendation_text', 'priority',
  'path_name', 'path_type', 'sequence', 'order', 'position', 'sort_order',
  'item_id', 'item_type', 'item_name',
  'correct', 'incorrect', 'accuracy', 'reaction_time',
  'attempts', 'successes', 'failures',
  'version', 'comparison_type', 'baseline_id', 'comparison_run_id',
  'improvement', 'change', 'delta',
  'caregiver_name', 'relationship', 'submitted_at',
  'answers', 'form_data', 'questionnaire_type',
  'target_age_min', 'target_age_max', 'age_range',
  'image_url', 'icon', 'color', 'thumbnail',
  'auth_id', 'external_id', 'uuid',
  'content', 'summary', 'details', 'body',
  'url', 'link', 'href',
  'enabled', 'visible', 'published',
  'start_date', 'end_date',
  'min_age', 'max_age',
  'tags', 'keywords',
  'progress', 'completion_percentage',
  'module_path_item_id', 'learning_module_id',
  'sensory_profile_id',
  'raw_scores', 'normalized_scores', 'percentile',
  'run_number', 'run_date',
  'child_age_months', 'child_age_at_assessment',
  'total_items', 'completed_items',
  'game_session_id',
  'stimulus', 'stimulus_type', 'response_type', 'response_time',
  'trial_number', 'trial_type',
  'is_correct', 'is_practice',
  'feedback', 'hint',
  'recommendation_type', 'recommended_module_id', 'reason',
  'questionnaire_data', 'raw_data',
  'submitted_by', 'reviewed_by', 'approved_by',
];

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'GET',
      headers: {
        'apikey': API_KEY,
        'Accept': 'application/json',
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.end();
  });
}

async function testColumn(table, col) {
  try {
    const url = `${BASE_URL}/${table}?select=${col}&limit=0`;
    const res = await fetchUrl(url);
    return res.status === 200 ? col : null;
  } catch (e) {
    return null;
  }
}

async function findColumns(table) {
  const BATCH_SIZE = 20;
  const foundColumns = [];
  
  for (let i = 0; i < COMMON_COLUMNS.length; i += BATCH_SIZE) {
    const batch = COMMON_COLUMNS.slice(i, i + BATCH_SIZE);
    const results = await Promise.all(batch.map(col => testColumn(table, col)));
    results.forEach(col => { if (col) foundColumns.push(col); });
  }
  
  return foundColumns;
}

async function main() {
  console.log('=== SUPABASE DATABASE SCHEMA DISCOVERY (FAST) ===\n');
  
  const schema = {};
  
  for (const table of TABLES) {
    process.stdout.write(`Scanning table: ${table}...`);
    const columns = await findColumns(table);
    schema[table] = columns;
    console.log(` Found ${columns.length} columns: ${columns.join(', ')}`);
  }
  
  console.log('\n=== COMPLETE SCHEMA SUMMARY ===\n');
  for (const [table, columns] of Object.entries(schema)) {
    console.log(`📋 ${table}:`);
    columns.forEach(col => console.log(`   - ${col}`));
    console.log('');
  }
  
  // Output as JSON for easy parsing
  console.log('\n=== JSON OUTPUT ===\n');
  console.log(JSON.stringify(schema, null, 2));
}

main().catch(console.error);
