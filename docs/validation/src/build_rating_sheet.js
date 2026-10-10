// Builds the expert content-validity rating sheet for Aumazing's
// questionnaires from templates.json (exported by
// packages/questionnaire_core/tool/export_templates.dart).
//
//   node docs/validation/src/build_rating_sheet.js
//
// Output: docs/validation/Aumazing_Expert_Content_Validity_Rating_Sheet.docx
// Formatting follows the capstone document standard: Times New Roman 12pt,
// black text, plain 1pt tables, captions above tables.

const fs = require('fs');
const path = require('path');
const {
  AlignmentType, BorderStyle, Document, Footer, HeadingLevel, LevelFormat,
  PageBreak, PageNumber, PageOrientation, Packer, Paragraph, ShadingType,
  Table, TableCell, TableRow, TextRun, WidthType,
} = require('docx');

const templates = require('./templates.json');
const OUT = path.join(__dirname, '..',
  'Aumazing_Expert_Content_Validity_Rating_Sheet.docx');

const FONT = 'Times New Roman';
const SIZE = 24; // half-points: 12pt
const BLACK = '000000';
const CONTENT_WIDTH = 12960; // landscape Letter, 1in margins

const run = (text, opts = {}) =>
  new TextRun({ text, font: FONT, size: SIZE, color: BLACK, ...opts });

const body = (text, opts = {}) => new Paragraph({
  children: Array.isArray(text) ? text : [run(text)],
  indent: { firstLine: 720 },
  spacing: { after: 120, line: 276 },
  ...opts,
});

const plain = (text, opts = {}) => new Paragraph({
  children: Array.isArray(text) ? text : [run(text)],
  spacing: { after: 80 },
  ...opts,
});

const heading = (text, level) => new Paragraph({
  heading: level,
  spacing: { before: 240, after: 120 },
  children: [run(text, { bold: true })],
});

const caption = (text) => new Paragraph({
  alignment: AlignmentType.LEFT,
  spacing: { before: 200, after: 80 },
  keepNext: true,
  children: [run(text, { bold: true })],
});

const bullet = (text) => new Paragraph({
  numbering: { reference: 'bullets', level: 0 },
  spacing: { after: 60 },
  children: Array.isArray(text) ? text : [run(text)],
});

// Writing lines. Word merges the borders of consecutive bordered
// paragraphs into one, so each line sits after an unbordered spacer.
const lines = (n) => Array.from({ length: n }, () => [
  new Paragraph({ spacing: { before: 0, after: 0 }, children: [run('')] }),
  new Paragraph({
    spacing: { before: 0, after: 0 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BLACK, space: 1 } },
    children: [run('')],
  }),
]).flat();

const border = { style: BorderStyle.SINGLE, size: 8, color: BLACK };
const borders = { top: border, bottom: border, left: border, right: border };

function cell(content, width, opts = {}) {
  const paras = (Array.isArray(content) ? content : [content]).map((c) =>
    c instanceof Paragraph
      ? c
      : new Paragraph({
          alignment: opts.center ? AlignmentType.CENTER : AlignmentType.LEFT,
          children: [run(String(c), { bold: !!opts.bold })],
        }));
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    shading: { type: ShadingType.CLEAR, fill: 'FFFFFF', color: 'auto' },
    margins: { top: 40, bottom: 40, left: 100, right: 100 },
    children: paras,
  });
}

function table(widths, header, rows, centerCols = []) {
  const total = widths.reduce((a, b) => a + b, 0);
  if (total !== CONTENT_WIDTH) {
    throw new Error(`Table is ${total} wide, not ${CONTENT_WIDTH}`);
  }
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({
        tableHeader: true,
        children: header.map((h, i) =>
          cell(h, widths[i], { bold: true, center: true })),
      }),
      ...rows.map((r) => new TableRow({
        cantSplit: true,
        children: r.map((c, i) =>
          cell(c, widths[i], { center: centerCols.includes(i) })),
      })),
    ],
  });
}

const SCALE = '1    2    3    4';
const YES_NO = 'Yes   No';

// ── Content ────────────────────────────────────────────────────────────

const domains = templates.home.domains;
const homeRows = templates.home.items.map((item, i) => [
  `A${i + 1}`, domains[item.domain], item.text, SCALE, SCALE, YES_NO, '',
]);

const describeOptions = (q) => {
  if (q.type === 'text') return ['Written answer'];
  return q.options.map((o) => new Paragraph({
    children: [run(`${o.label}${o.flag ? ' *' : ''}`)],
  }));
};

const obsItems = templates.observation.items;
const obsRows = obsItems.map((q, i) => [
  `B${i + 1}`,
  q.scope === 'game' ? 'Each game' : 'Once',
  q.text,
  describeOptions(q),
  SCALE, SCALE, YES_NO, '',
]);

const intakeRows = [
  ['C1', 'Who is watching?', ['Parent', 'Guardian', 'SPED teacher', 'Therapist']
    .map((t) => new Paragraph({ children: [run(t)] })), SCALE, YES_NO, ''],
  ...templates.intake.items.map((q, i) => [
    `C${i + 2}`, q.text, describeOptions(q), SCALE, YES_NO, '',
  ]),
];

const flagged = obsItems.flatMap((q) =>
  (q.options || []).filter((o) => o.flag).map((o) => `"${o.label}" (${q.text.replace(/:$/, '')}): ${o.flag}`));

const children = [
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 60 },
    children: [run('AUMAZING OBSERVATION QUESTIONNAIRES', { bold: true })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 240 },
    children: [run('EXPERT CONTENT VALIDITY RATING SHEET', { bold: true })],
  }),

  heading('1 EXPERT INFORMATION', HeadingLevel.HEADING_1),
  caption('Table 1.1. Expert Information'),
  table([3600, 9360], ['Item', 'Answer'], [
    ['Full name', ''],
    ['Profession (e.g., SPED teacher, OT, SLP, developmental pediatrician)', ''],
    ['PRC licence number (if any)', ''],
    ['Years of experience with autistic children', ''],
    ['School, center or clinic', ''],
    ['Date of rating', ''],
  ]),

  heading('2 PURPOSE', HeadingLevel.HEADING_1),
  body('Aumazing is a game-based learning app for children on the autism spectrum. Each child plays a short set of assessment games before (pre-assessment) and after (post-assessment) a learning period. While the child plays, a parent, guardian, SPED teacher or therapist sits beside the child and watches. Nothing is asked during play. The adult answers questions only before the child starts and after the child finishes.'),
  body('The questions were written by the proponents and have not yet been validated. This sheet asks you, as an expert, to judge whether each question is relevant to what it is meant to capture and whether it is worded clearly. Your ratings will be used to compute content validity indices, and your comments will be used to revise the questions before they are used with families.'),
  body('The answers never change a game score and are not used to diagnose. They are shown beside the game results so that a parent or teacher can read the scores in context, for example knowing that the child needed help or was unwell that day.'),

  heading('3 INSTRUCTIONS', HeadingLevel.HEADING_1),
  body('For each question, circle one number for Relevance and one for Clarity using the scales in Table 3.1. Where a column asks Yes or No, circle one. Please write a suggested rewording in the Comments column for any question you rate 1 or 2, or that you would change.'),
  caption('Table 3.1. Rating Scales'),
  table([1400, 5780, 5780], ['Score', 'Relevance', 'Clarity'], [
    ['1', 'Not relevant', 'Not clear'],
    ['2', 'Somewhat relevant (needs major revision)', 'Somewhat clear (needs major revision)'],
    ['3', 'Quite relevant (needs minor revision)', 'Quite clear (needs minor revision)'],
    ['4', 'Highly relevant', 'Very clear'],
  ], [0]),
  body('Please rate the questions independently, without discussing them with other experts, so that each rating reflects your own judgement.'),

  new Paragraph({ children: [new PageBreak()] }),
  heading('4 PART A. HOME QUESTIONNAIRE', HeadingLevel.HEADING_1),
  body(`The parent answers these after each assessment. The introduction reads: "${templates.home.intro}" Each statement is answered Never, Rarely, Sometimes, Often or Always. Every statement is phrased so that Always is the more developed end, and each belongs to one of four areas the games also report on: ${Object.values(domains).join(', ')}.`),
  body('Relevance: does the statement describe an everyday behaviour that reflects the stated area for children on the autism spectrum? Right area: does the statement belong to the area shown?'),
  caption('Table 4.1. Home Questionnaire Items'),
  table([600, 1500, 4060, 1500, 1500, 1300, 2500],
    ['No.', 'Area', 'Statement', 'Relevance', 'Clarity', 'Right area?', 'Comments / suggested wording'],
    homeRows, [0, 3, 4, 5]),

  new Paragraph({ children: [new PageBreak()] }),
  heading('5 PART B. AFTER THE SESSION ("WHAT DID YOU SEE?")', HeadingLevel.HEADING_1),
  body(`The adult who watched answers these after the child's last game and before any result is shown. The introduction reads: "${templates.observation.intro}" Questions marked "Each game" are asked once for every game the child played; the others are asked once for the session.`),
  body('Relevance: does the question capture something about the session that a reader of the game score should know? Answer choices: are the choices complete, distinct and appropriate? Answers marked with an asterisk (*) are highlighted beside the game score as a flag (see Table 5.2).'),
  caption('Table 5.1. After-Session Questions'),
  table([600, 1000, 2400, 2760, 1500, 1500, 1300, 1900],
    ['No.', 'Asked', 'Question', 'Answer choices', 'Relevance', 'Clarity', 'Choices OK?', 'Comments'],
    obsRows, [0, 1, 4, 5, 6]),
  caption('Table 5.2. Answers Shown as Flags Beside the Game Score'),
  table([7960, 1500, 3500], ['Answer (question): flag shown', 'Keep flag?', 'Comments'],
    flagged.map((f) => [f, YES_NO, '']), [1]),

  new Paragraph({ children: [new PageBreak()] }),
  heading('6 PART C. BEFORE THE SESSION ("BEFORE YOUR CHILD STARTS")', HeadingLevel.HEADING_1),
  body(`The adult answers these before the first game. The introduction reads: "${templates.intake.intro}" Only "Who is watching?" is required; the background questions are optional and describe the child. They are not scored.`),
  body('Please rate Clarity, and whether the answer choices are complete and appropriate for families and schools in the Philippines, for example whether the school levels match how SPED placement is described locally, and whether the diagnosis question is worded sensitively.'),
  caption('Table 6.1. Before-Session Questions'),
  table([600, 2800, 4060, 1500, 1300, 2700],
    ['No.', 'Question', 'Answer choices', 'Clarity', 'Choices OK?', 'Comments / missing choices'],
    intakeRows, [0, 3, 4]),

  new Paragraph({ children: [new PageBreak()] }),
  heading('7 PART D. OVERALL JUDGEMENT', HeadingLevel.HEADING_1),
  plain([run('D1. ', { bold: true }), run('Which everyday behaviours that you consider important are missing from Part A? Please suggest statements and their area.')]),
  ...lines(2),
  plain([run('D2. ', { bold: true }), run('Are Never, Rarely, Sometimes, Often and Always suitable answer choices for Part A? If not, what would you use?')], { spacing: { before: 240, after: 80 } }),
  ...lines(1),
  plain([run('D3. ', { bold: true }), run('Is there anything else the watching adult should report after the session (Part B)?')], { spacing: { before: 240, after: 80 } }),
  ...lines(1),
  plain([run('D4. ', { bold: true }), run('Other comments on the questionnaires as a whole.')], { spacing: { before: 240, after: 80 } }),
  ...lines(2),
  plain([run('I rated the questions above independently and to the best of my professional judgement.')], { spacing: { before: 240, after: 80 } }),
  ...lines(1),
  plain('Signature over printed name'),
  ...lines(1),
  plain('Date'),

  new Paragraph({ children: [new PageBreak()] }),
  heading('APPENDIX. HOW THE RATINGS ARE SCORED', HeadingLevel.HEADING_1),
  body('This page is for the proponents. The ratings are entered in the companion workbook (Aumazing_Content_Validity_Calculator.xlsx), which computes the indices below.'),
  bullet([run('Item-level content validity index (I-CVI): ', { bold: true }), run('the proportion of experts who rated an item 3 or 4 for relevance. With three to five experts every expert must agree (I-CVI = 1.00); with six or more experts the I-CVI should be at least .78 (Lynn, 1986; Polit & Beck, 2006).')]),
  bullet([run('Modified kappa (k*): ', { bold: true }), run('the I-CVI adjusted for chance agreement. Values above .74 are excellent, .60 to .74 good, and .40 to .59 fair (Polit, Beck, & Owen, 2007).')]),
  bullet([run('Scale-level index (S-CVI/Ave): ', { bold: true }), run('the average I-CVI across the items of a part; .90 or higher indicates excellent content validity (Polit & Beck, 2006).')]),
  bullet([run('Clarity: ', { bold: true }), run('computed the same way. It is not a validity index, but items with low clarity are reworded using the experts\' suggestions.')]),
  body('Items that do not meet the thresholds are revised using the comments and rated again, or removed. The version that meets them is entered in the Aumazing practitioner portal and marked validated. Content validity is the first step; after a pilot with parents, internal consistency (Cronbach\'s alpha) is computed for each area of Part A.'),
  heading('References', HeadingLevel.HEADING_2),
  plain('Lynn, M. R. (1986). Determination and quantification of content validity. Nursing Research, 35(6), 382–385.', { indent: { left: 720, hanging: 720 } }),
  plain('Polit, D. F., & Beck, C. T. (2006). The content validity index: Are you sure you know what\'s being reported? Critique and recommendations. Research in Nursing & Health, 29(5), 489–497.', { indent: { left: 720, hanging: 720 } }),
  plain('Polit, D. F., Beck, C. T., & Owen, S. V. (2007). Is the CVI an acceptable indicator of content validity? Appraisal and recommendations. Research in Nursing & Health, 30(4), 459–467.', { indent: { left: 720, hanging: 720 } }),
];

const doc = new Document({
  creator: 'Aumazing proponents',
  title: 'Aumazing Expert Content Validity Rating Sheet',
  styles: {
    default: { document: { run: { font: FONT, size: SIZE, color: BLACK } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FONT, size: SIZE, bold: true, color: BLACK },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FONT, size: SIZE, bold: true, color: BLACK },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: {
    config: [{
      reference: 'bullets',
      levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
    }],
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840, orientation: PageOrientation.LANDSCAPE },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [run('Page '), new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: SIZE, color: BLACK })],
        })],
      }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(OUT, buf);
  console.log(`Wrote ${OUT}`);
});
