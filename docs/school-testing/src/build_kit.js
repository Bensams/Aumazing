// Builds the school testing kit (Kindergarten and Grade 1) as Word files:
// letters, study summary, parent consent (English and Bisaya), child assent
// script, testing-day forms, thank-you letter and certificates.
//
//   node docs/school-testing/src/build_kit.js        # needs the docx npm package
//
// Values come from config.json beside this file. Anything still in
// [brackets] there prints as a blank to fill by hand.
// Formatting follows the capstone document standard: Times New Roman 12pt,
// black text, plain 1pt tables, captions above tables.

const fs = require('fs');
const path = require('path');
const {
  AlignmentType, BorderStyle, Document, Footer, LevelFormat, PageBreak,
  PageNumber, PageOrientation, Packer, Paragraph, ShadingType, Table, TableCell, TableRow,
  TextRun, WidthType,
} = require('docx');

const cfg = require('./config.json');
const OUT_DIR = path.join(__dirname, '..');

const FONT = 'Times New Roman';
const SIZE = 24; // half-points: 12pt
const BLACK = '000000';
const CONTENT_WIDTH = 9360; // Letter, 1in margins

const PROPONENTS = [
  ['Benedict Paul S. Samson', 'Proponent'],
  ['Ruel Jr. A. Mendio', 'Proponent'],
];
const ADVISER = ['Ms. Christine Marie D. Ordaneza, LPT', 'Capstone Adviser'];
const TITLE = 'Aumazing: A Gamified Learning App for Children with Early ' +
  'Childhood Autism Spectrum Disorder';

// ---------------------------------------------------------------- text

// {key} -> config value. **bold** and ~italic~ become runs.
const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => {
  if (!(k in cfg)) throw new Error(`config.json has no "${k}"`);
  return cfg[k];
});

const run = (text, opts = {}) =>
  new TextRun({ text, font: FONT, size: SIZE, color: BLACK, ...opts });

function runs(s, opts = {}) {
  return fill(s).split(/(\*\*[^*]+\*\*|~[^~]+~)/).filter(Boolean).map((part) => {
    if (part.startsWith('**')) return run(part.slice(2, -2), { ...opts, bold: true });
    if (part.startsWith('~')) return run(part.slice(1, -1), { ...opts, italics: true });
    return run(part, opts);
  });
}

const para = (s, opts = {}, runOpts = {}) => new Paragraph({
  children: Array.isArray(s) ? s : runs(s, runOpts),
  spacing: { after: 120 },
  ...opts,
});

const body = (s) => para(s, { indent: { firstLine: 720 }, alignment: AlignmentType.JUSTIFIED });
const plain = (s, opts = {}, runOpts = {}) => para(s, { spacing: { after: 0 }, ...opts }, runOpts);
const center = (s, runOpts = {}, opts = {}) =>
  para(s, { alignment: AlignmentType.CENTER, spacing: { after: 0 }, ...opts }, runOpts);
const blank = () => plain('');
const heading = (s) => para(s.toUpperCase(), {
  alignment: AlignmentType.CENTER, spacing: { before: 120, after: 240 }, keepNext: true,
}, { bold: true });
const subheading = (s) => para(s, { spacing: { before: 200, after: 100 }, keepNext: true }, { bold: true });
const caption = (s) => para(s, { alignment: AlignmentType.LEFT, spacing: { before: 200, after: 80 }, keepNext: true }, { bold: true });
const bullet = (s) => para(s, { numbering: { reference: 'bullets', level: 0 }, spacing: { after: 80 } });
const numbered = (ref) => (s) => para(s, { numbering: { reference: ref, level: 0 }, spacing: { after: 80 } });
const check = (s) => para(`☐  ${s}`, { indent: { left: 720, hanging: 360 }, spacing: { after: 80 } });
const pageBreak = () => new Paragraph({ children: [new PageBreak()] });

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

// --------------------------------------------------------------- tables

const line1pt = { style: BorderStyle.SINGLE, size: 8, color: BLACK };
const none = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
const BORDERS = { top: line1pt, bottom: line1pt, left: line1pt, right: line1pt };
const NO_BORDERS = { top: none, bottom: none, left: none, right: none };

function cell(content, width, { bold = false, borders = BORDERS, span } = {}) {
  const items = Array.isArray(content) ? content : [content];
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    columnSpan: span,
    shading: { type: ShadingType.CLEAR, fill: 'FFFFFF', color: 'auto' },
    margins: { top: 40, bottom: 40, left: 100, right: 100 },
    children: items.map((c) => (c instanceof Paragraph
      ? c : para(String(c), { spacing: { after: 0 } }, { bold }))),
  });
}

function table(headers, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const head = headers && new TableRow({
    tableHeader: true,
    children: headers.map((h, i) => cell(h, widths[i], { bold: true })),
  });
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      ...(head ? [head] : []),
      ...rows.map((r) => new TableRow({
        children: r.map((c, i) => cell(c, widths[i])),
      })),
    ],
  });
}

const emptyRows = (n, cols) => Array.from({ length: n }, () => Array(cols).fill(''));

// Two-column label / value table, e.g. the study summary.
const factTable = (rows, labelWidth = 2600) =>
  table(null, rows.map(([k, v]) => [para(k, { spacing: { after: 0 } }, { bold: true }), v]),
    [labelWidth, CONTENT_WIDTH - labelWidth]);

// ----------------------------------------------------------- signatures

const sigLines = ([name, role]) => [
  blank(), blank(),
  plain('______________________________'),
  plain(name, {}, { bold: true }),
  plain(role),
];

// Signers laid out two per row in a borderless table.
function signatures(signers, width = CONTENT_WIDTH) {
  const half = width / 2;
  const rows = [];
  for (let i = 0; i < signers.length; i += 2) {
    rows.push(new TableRow({
      children: [signers[i], signers[i + 1]].map((s) =>
        cell(s ? sigLines(s) : blank(), half, { borders: NO_BORDERS })),
    }));
  }
  return new Table({
    width: { size: width, type: WidthType.DXA },
    columnWidths: [half, half],
    borders: { ...NO_BORDERS, insideHorizontal: none, insideVertical: none },
    rows,
  });
}

const labelled = (label, signer) => [
  para(label, { spacing: { before: 240, after: 0 }, keepNext: true }),
  ...sigLines(signer).slice(1),
];

const approval = (signer) => [
  para('☐ Approved     ☐ Disapproved', { spacing: { before: 240, after: 0 } }),
  ...sigLines(signer).slice(1),
  plain('Date: ____________________'),
];

// ------------------------------------------------------------- letters

const letterhead = () => [
  center('ASSUMPTION COLLEGE OF DAVAO', { bold: true }),
  center('Faculty of Information Technology'),
  center('Bachelor of Science in Information Technology'),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 240 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: BLACK, space: 4 } },
    children: [run('Davao City')],
  }),
];

function letter({ to, thru, salutation, paragraphs, closing = 'Respectfully yours,',
  signers = PROPONENTS, after = [] }) {
  return [
    ...letterhead(),
    plain('{letter_date}', { spacing: { after: 240 } }),
    ...to.map((l, i) => plain(l, {}, i === 0 ? { bold: true } : {})),
    ...(thru ? [para(`Thru: ${thru}`, { spacing: { before: 200, after: 0 } })] : []),
    para(salutation, { spacing: { before: 240, after: 200 } }),
    ...paragraphs,
    para(closing, { spacing: { before: 200, after: 0 } }),
    signatures(signers),
    ...after,
  ];
}

const studyIntro =
  `We are fourth-year Bachelor of Science in Information Technology students of
  Assumption College of Davao, currently completing our capstone project entitled
  **"${TITLE}."** Aumazing is a tablet and web application with short,
  sensory-friendly learning games for young children, built around communication,
  social interaction and play skills, and developed with the guidance of SPED
  teachers.`.replace(/\s+/g, ' ');

const contactLine = (verb = 'For any question, you may reach us') =>
  body(`${verb} at {contact_number} or {contact_email}.`);

// ------------------------------------------------------------ documents

function studySummary() {
  return [
    heading('Study Summary'),
    caption('Table 1. Summary of the School Testing of Aumazing'),
    factTable([
      ['Title', TITLE],
      ['Proponents', 'Benedict Paul S. Samson and Ruel Jr. A. Mendio, BSIT, Assumption College of Davao'],
      ['Capstone Adviser', ADVISER[0]],
      ['Purpose of the testing', 'To find out whether Kindergarten and Grade 1 learners can understand and enjoy the games, whether the app runs reliably on the tablets, and whether teachers find it usable and appropriate for young learners.'],
      ['Participants', 'About {participant_count} Kindergarten and Grade 1 learners of {school_name} whose parents or guardians gave written consent and who agree to play. Their class advisers and the SPED teacher take part as observers.'],
      ['Schedule and venue', '{testing_dates}, within {testing_hours}, in {venue}. Times are agreed with the class advisers so that no lesson, test or recess is missed.'],
      ['What the child does', 'Plays on a tablet, one child at a time, with a teacher present. First session: a short "learn first" warm-up on the shapes, colors and objects used in the games, then four short games (Copy Me, Match It, Do What I Say, My Turn Your Turn). Middle sessions: short learning activities. Last session: the same four games again.'],
      ['How long', 'About 15 to 20 minutes per session, with breaks whenever the child needs them.'],
      ['What the adults do', 'The observing teacher answers short questions in the app before and after the games (about 3 to 5 minutes). At the end, teachers answer a usability questionnaire (about 10 minutes).'],
      ['Data collected', 'Gameplay information only: scores, response times, taps, hints and idle time, plus the observer\'s answers. The app does not use the camera, microphone or location. Each child is entered in the app by a code (for example K-01), never by name.'],
      ['Data protection', 'Handled under the Data Privacy Act of 2012 (RA 10173). Data is kept on the proponents\' tablets and in the project\'s password-protected online database, seen only by the proponents and the capstone adviser, reported only as group results, and deleted after {data_deletion_date}. Signed forms and the code list are kept in a sealed envelope.'],
      ['Possible risks', 'Minimal: tiredness, boredom or mild frustration with a game. These are reduced by short sessions, breaks, low-sensory settings and the child\'s right to stop at any time.'],
      ['Possible benefits', 'Enjoyable learning activities for the child; teachers try a free learning tool; the school receives a summary of the overall results.'],
      ['Important', 'Aumazing does not diagnose autism or any other condition and does not replace licensed professionals. Results are not used for grades, placement or any school record. Taking part is voluntary and can be stopped at any time without any consequence.'],
      ['Contact', 'Benedict Paul S. Samson and Ruel Jr. A. Mendio, {contact_number}, {contact_email}'],
    ]),
  ];
}

function sdsLetter() {
  return letter({
    to: ['{sds_name}', '{sds_position}', '{division_name}', '{division_address}'],
    thru: '[Chief, School Governance and Operations Division, or as the Division Office directs]',
    salutation: 'Dear Sir/Madam:',
    paragraphs: [
      body('Greetings of peace!'),
      body(studyIntro),
      body('In accordance with DepEd Order No. 16, s. 2017 (Research Management Guidelines), we respectfully request your permission to conduct user acceptance testing of the application with Kindergarten and Grade 1 learners of {school_name} on {testing_dates}, subject to the approval of the School Principal.'),
      body('The testing involves about {participant_count} learners whose parents or guardians have given written consent. Each child plays the games one at a time, for about 15 to 20 minutes per session, with a teacher present at all times. Sessions are arranged with the class advisers so that no lesson is missed. There is no cost to the school, the learners or the parents.'),
      body('We commit to the following safeguards: voluntary participation with parental consent and the child\'s own assent; collection of gameplay information only, with no use of the camera, microphone or location; identification of learners by code rather than by name; handling of all data in accordance with the Data Privacy Act of 2012 (RA 10173); and adherence to the DepEd Child Protection Policy (DepEd Order No. 40, s. 2012). The application does not diagnose any condition, and its results will not be used for grading or placement.'),
      body('Attached are the endorsement of our capstone adviser, the study summary, the letters to the school, the parent consent form and the child assent script. We will gladly submit any other document the Division requires.'),
      contactLine(),
      body('Thank you very much, and we hope for your favorable action.'),
    ],
    after: [
      ...labelled('Noted by:', ADVISER),
      ...labelled('Recommending approval:', ['{dean_name}', '{dean_position}']),
    ],
  });
}

function principalLetter() {
  return letter({
    to: ['{principal_name}', '{principal_position}', '{school_name}', '{school_address}'],
    salutation: 'Dear {principal_salutation}:',
    paragraphs: [
      body('Greetings of peace!'),
      body(studyIntro),
      body('In line with this, we respectfully request your permission to conduct user acceptance testing of the application with Kindergarten and Grade 1 learners of {school_name} on {testing_dates}. The testing will show us whether young children can understand and enjoy the games, and whether teachers find the app usable and appropriate.'),
      body('If permitted, the testing will be carried out as follows:'),
      bullet('**Participants.** About {participant_count} Kindergarten and Grade 1 learners whose parents or guardians have given written consent, with their class advisers and the school\'s SPED teacher as observers.'),
      bullet('**Sessions.** One child at a time, for about 15 to 20 minutes, in {venue}, within {testing_hours}. A teacher is present at all times, and the proponents never stay alone with a child. Times are agreed with the class advisers so that no lesson, test or recess is missed.'),
      bullet('**Activities.** A short "learn first" warm-up, four short assessment games, a few short learning sessions, and a final round of the same four games.'),
      bullet('**Materials.** The proponents bring their own tablets. There is no cost to the school or to the parents.'),
      body('We assure you of the following:'),
      bullet('Participation is voluntary. A child takes part only with a parent\'s or guardian\'s signed consent and the child\'s own agreement, and may stop at any time without any consequence.'),
      bullet('The app records gameplay information only. It does not use the camera, microphone or location. Learners are identified by code, not by name, and all data is handled in accordance with the Data Privacy Act of 2012 (RA 10173).'),
      bullet('Aumazing does not diagnose autism or any other condition. Results are not used for grading, placement or any school record.'),
      bullet('We will follow the school\'s child protection policy and the instructions of the school staff at all times.'),
      bullet('A summary of the overall results will be given to the school after the study.'),
      body('Attached for your reference are the study summary, the endorsement of our capstone adviser, the letters to the class advisers, the SPED teacher and the parents, the parent consent form and the child assent script.'),
      contactLine(),
      body('We hope for your favorable response. Thank you very much.'),
    ],
    after: [
      ...labelled('Noted by:', ADVISER),
      ...labelled('Recommending approval:', ['{dean_name}', '{dean_position}']),
      ...approval(['{principal_name}', '{principal_position}']),
    ],
  });
}

function adviserEndorsement() {
  return [
    ...letterhead(),
    plain('{letter_date}', { spacing: { after: 240 } }),
    plain('{principal_name}', {}, { bold: true }),
    plain('{principal_position}'),
    plain('{school_name}'),
    plain('{school_address}'),
    para('Dear {principal_salutation}:', { spacing: { before: 240, after: 200 } }),
    body('Greetings of peace!'),
    body(`This is to endorse **Mr. Benedict Paul S. Samson** and **Mr. Ruel Jr. A. Mendio**, fourth-year Bachelor of Science in Information Technology students of Assumption College of Davao, who are completing their capstone project entitled **"${TITLE}."**`),
    body('User acceptance testing with young learners is a required part of their capstone. The proponents wish to conduct this testing with Kindergarten and Grade 1 learners of your school on {testing_dates}, under the conditions stated in their letter: voluntary participation with parental consent and child assent, short supervised sessions, collection of gameplay information only, and handling of all data in accordance with the Data Privacy Act of 2012 (RA 10173).'),
    body('I am their capstone adviser and will supervise the conduct of the testing. Any concern about the activity may be raised directly with me through the Faculty of Information Technology.'),
    body('Your kind approval of their request will be greatly appreciated.'),
    para('Respectfully yours,', { spacing: { before: 200, after: 0 } }),
    ...sigLines(ADVISER).slice(1),
    ...labelled('Noted by:', ['{dean_name}', '{dean_position}']),
  ];
}

function classAdviserLetter() {
  const n = numbered('advisers');
  return letter({
    to: ['{kinder_adviser}', 'Kindergarten Class Adviser', '', '{grade1_adviser}', 'Grade 1 Class Adviser', '{school_name}']
      .map((l, i) => (i === 3 ? `**${l}**` : l)),
    salutation: 'Dear Ma\'am/Sir:',
    paragraphs: [
      body('Greetings of peace!'),
      body(studyIntro),
      body('With the approval of {principal_name}, we will test the application with Kindergarten and Grade 1 learners on {testing_dates}. Because you know your learners best, we respectfully ask for your help. Specifically, we request you to:'),
      n('Send home the parent letter and consent form with each learner in your class, and collect the signed forms by {reply_by_date}. Only learners with a signed form will take part. We will not ask you for class lists, records or diagnoses.'),
      n('Agree with us on session times that do not interfere with lessons, tests or recess.'),
      n('Accompany each learner to the testing area, or stay in the room during the session. A teacher is present at all times; we never stay alone with a child.'),
      n('Watch the session when you can, and answer the short questions in the app before and after the games (about 3 to 5 minutes per child). The questions on diagnosis and therapy are optional; please answer them only if the parent allowed it on the consent form.'),
      n('At the end of the testing, answer a short usability questionnaire about the app (about 10 minutes).'),
      body('You may stop any session if a learner seems upset, tired or unwilling. The learner\'s comfort always comes first.'),
      body('Your help is voluntary. As thanks, we will give each participating teacher a certificate of appreciation and, with your permission, acknowledge you in our manuscript.'),
      contactLine(),
      body('Thank you very much for your time and support.'),
    ],
    after: [...labelled('Noted by:', ['{principal_name}', '{principal_position}'])],
  });
}

function spedLetter() {
  const n = numbered('sped');
  return letter({
    to: ['{sped_teacher}', 'SPED Teacher', '{school_name}'],
    salutation: 'Dear Ma\'am/Sir:',
    paragraphs: [
      body('Greetings of peace!'),
      body(studyIntro),
      body('With the approval of {principal_name}, we will test the application with Kindergarten and Grade 1 learners on {testing_dates}. Because of your expertise in working with young learners with special needs, we respectfully invite you to serve as the SPED observer and expert evaluator for the testing. If you agree, we would ask you to:'),
      n('Before the testing, go over the session plan and the games with us (about 30 minutes) and tell us any adjustment needed for young learners, such as breaks, sound level or simpler instructions.'),
      n('With the class advisers, help us prepare for learners who may need extra support during sessions, so that the right sensory settings and breaks are ready. We do not need to see any learner\'s records.'),
      n('Observe sessions, especially those of learners who need more support, and answer the short questions in the app before and after the games (about 3 to 5 minutes per child).'),
      n('Pause or stop any session when a learner shows distress. Your judgment on this is final.'),
      n('After the testing, give your professional view of the app through the usability questionnaire (about 10 minutes) and, if you are willing, rate the questionnaire items in our Expert Content-Validity Rating Sheet (about 30 to 45 minutes).'),
      body('Your participation is voluntary, and you may decline any part of this request. As thanks, we will give you a certificate of appreciation and, with your permission, acknowledge you as an expert evaluator in our manuscript.'),
      contactLine(),
      body('Thank you very much for considering our request.'),
    ],
    after: [
      para('Conforme:', { spacing: { before: 240, after: 0 } }),
      ...sigLines(['{sped_teacher}', 'SPED Teacher']).slice(1),
      plain('Date: ____________________'),
      ...labelled('Noted by:', ['{principal_name}', '{principal_position}']),
    ],
  });
}

// Parent letter + consent form, in either language.
const PARENT = {
  en: {
    title: 'Letter to Parents and Guardians',
    salutation: 'Dear Parent or Guardian:',
    paragraphs: [
      'Greetings of peace!',
      'We are Benedict Paul S. Samson and Ruel Jr. A. Mendio, Bachelor of Science in Information Technology students of Assumption College of Davao. For our capstone project we made **Aumazing**, a tablet app with short, gentle games that help young children learn communication, social interaction and play skills. The app was designed for young children with autism spectrum disorder, and we are also trying it with young learners in general to see whether the games are easy to understand and enjoyable.',
      'We are inviting your child because your child is in Kindergarten or Grade 1 at {school_name}. **Being invited does not mean that your child has, or is suspected of having, any condition.**',
    ],
    whatTitle: 'What your child will do',
    what: [
      'Play on a tablet, one child at a time, for about 15 to 20 minutes per session, in {venue}. A teacher is always present.',
      'Sessions happen on {testing_dates}, at times agreed with the class adviser so that no lesson is missed.',
      'The teacher or SPED teacher who watches will answer short questions in the app about what they saw while your child played.',
    ],
    promiseTitle: 'Our promise to you',
    promise: [
      'Taking part is voluntary. You may say no, or stop at any time, with no effect on your child\'s grades or treatment at school.',
      'We will also ask your child if they want to play. If your child does not want to, or wants to stop, we will not insist.',
      'The app records gameplay information only (scores, response times, taps and hints). It does not use the camera, microphone or location. Your child is entered in the app by a code, not by name.',
      'Aumazing does not diagnose autism or any other condition. Results are not used for grades or any school record.',
      'All information is protected under the Data Privacy Act of 2012 (RA 10173), reported only as group results, and deleted after {data_deletion_date}.',
      'There is no fee and no cost to you. Your child will receive a small sticker as thanks, whether or not they finish.',
    ],
    closingText: [
      'If you agree, please sign the consent form attached and return it to the class adviser by {reply_by_date}. If you have questions, you may reach us at {contact_number} or {contact_email}, or ask the class adviser.',
      'Thank you very much!',
    ],
    closing: 'Respectfully yours,',
    formTitle: 'Parent or Guardian Consent Form',
    formIntro: `Study: ${TITLE}. Proponents: Benedict Paul S. Samson and Ruel Jr. A. Mendio, Assumption College of Davao.`,
    tableCaption: 'Table 1. Consent Choices',
    cols: ['Item', 'Please check one', ''],
    yes: '☐ Yes', no: '☐ No',
    items: [
      '1. I allow my child to take part in the testing of Aumazing.',
      '2. I allow the teacher or SPED teacher who watches to answer short questions in the app about how my child did during the games.',
      '3. (Optional) I allow the teacher to note in the app whether my child has a diagnosis or receives therapy.',
      '4. (Optional) I allow my child\'s gameplay data, without the name, to be used to improve the app\'s recommendation model.',
      '5. (Optional) I allow photos of the session for the research report, taken from behind or showing only hands and the tablet. No face will be shown.',
      '6. (Optional) I am willing to answer a short questionnaire about my child before and after the testing (about 10 minutes each).',
    ],
    statement: 'I have read this letter, or it was read to me, and I understood it. My questions were answered. I know that I may withdraw my child at any time by telling the class adviser or the proponents, and that my child\'s data will then be deleted.',
    fieldsCaption: 'Table 2. Child and Parent or Guardian Details',
    fields: [
      'Child\'s name', 'Grade and section', 'Child\'s birth month and year (for age-appropriate games)',
      'Anything we should know (for example, sensitive to loud sounds)',
      'Parent or guardian\'s name and relationship to the child', 'Contact number',
      'Signature and date',
    ],
  },
  ceb: {
    title: 'Sulat para sa mga Ginikanan ug Guardian',
    salutation: 'Minahal namong Ginikanan o Guardian:',
    paragraphs: [
      'Maayong adlaw!',
      'Kami si Benedict Paul S. Samson ug Ruel Jr. A. Mendio, mga estudyante sa Bachelor of Science in Information Technology sa Assumption College of Davao. Para sa among capstone project, naghimo kami og **Aumazing**, usa ka app sa tablet nga adunay mubo ug malumo nga mga dula nga makatabang sa gagmay nga mga bata sa pagkat-on og komunikasyon, pakig-uban sa uban, ug pagdula. Gihimo ang app alang sa gagmay nga mga bata nga adunay autism spectrum disorder, ug gisulayan usab namo kini sa mga batang estudyante sa kinatibuk-an aron mahibaw-an kung sayon ba sabton ug makalingaw ba ang mga dula.',
      'Gidapit namo ang imong anak tungod kay Kindergarten o Grade 1 siya sa {school_name}. **Ang pagdapit wala magpasabot nga ang imong anak adunay, o gidudahang adunay, bisan unsang kondisyon.**',
    ],
    whatTitle: 'Unsa ang buhaton sa imong anak',
    what: [
      'Magdula siya sa tablet, usa-usa ka bata matag higayon, mga 15 hangtod 20 ka minuto matag sesyon, sa {venue}. Kanunay nga adunay magtutudlo nga kauban.',
      'Himoon ang mga sesyon sa {testing_dates}, sa oras nga gikasabutan uban sa class adviser aron walay leksyon nga mabiyaan.',
      'Ang magtutudlo o SPED teacher nga nagtan-aw motubag og mubo nga mga pangutana sa app bahin sa iyang nakita samtang nagdula ang imong anak.',
    ],
    promiseTitle: 'Ang among saad kanimo',
    promise: [
      'Boluntaryo ang pag-apil. Mahimo kang modumili o mohunong bisan kanus-a, ug walay epekto kini sa grado o sa pagtratar sa imong anak sa eskwelahan.',
      'Pangutan-on usab namo ang imong anak kung gusto ba siyang modula. Kung dili siya gusto, o gusto na siyang mohunong, dili namo siya pugson.',
      'Ang app motala lamang sa impormasyon sa pagdula (score, gidugayon sa pagtubag, mga tap ug mga hint). Dili kini mogamit sa camera, mikropono o lokasyon. Code ang ibutang sa app para sa imong anak, dili ang iyang ngalan.',
      'Ang Aumazing dili modiagnose sa autism o bisan unsang kondisyon. Dili gamiton ang resulta sa grado o sa bisan unsang rekord sa eskwelahan.',
      'Ang tanang impormasyon protektado ubos sa Data Privacy Act of 2012 (RA 10173), ireport lamang isip resulta sa tibuok grupo, ug papason human sa {data_deletion_date}.',
      'Walay bayad ug walay gasto alang kanimo. Makadawat ang imong anak og gamay nga sticker isip pasalamat, mahuman man niya o dili.',
    ],
    closingText: [
      'Kung mouyon ka, palihug pirmahi ang kauban nga consent form ug ibalik sa class adviser sa dili pa ang {reply_by_date}. Kung aduna kay pangutana, kontaka kami sa {contact_number} o {contact_email}, o pangutan-a ang class adviser.',
      'Daghang salamat!',
    ],
    closing: 'Matinahuron,',
    formTitle: 'Porma sa Pagtugot sa Ginikanan o Guardian (Consent Form)',
    formIntro: `Pagtuon: ${TITLE}. Mga proponent: Benedict Paul S. Samson ug Ruel Jr. A. Mendio, Assumption College of Davao.`,
    tableCaption: 'Table 1. Mga Pagpili sa Pagtugot',
    cols: ['Butang', 'Pili og usa', ''],
    yes: '☐ Oo', no: '☐ Dili',
    items: [
      '1. Gitugotan nako ang akong anak nga moapil sa pagsulay sa Aumazing.',
      '2. Gitugotan nako ang magtutudlo o SPED teacher nga nagtan-aw nga motubag og mubo nga mga pangutana sa app bahin sa pagdula sa akong anak.',
      '3. (Opsyonal) Gitugotan nako ang magtutudlo nga isulat sa app kung ang akong anak adunay diagnosis o nagpa-therapy.',
      '4. (Opsyonal) Gitugotan nako nga ang datos sa pagdula sa akong anak, nga walay ngalan, gamiton aron mapalambo ang recommendation model sa app.',
      '5. (Opsyonal) Gitugotan nako ang pagkuha og litrato sa sesyon para sa research report, gikan sa likod o kamot ug tablet lamang. Walay nawong nga ipakita.',
      '6. (Opsyonal) Andam ko motubag og mubo nga questionnaire bahin sa akong anak sa wala pa ug human sa pagsulay (mga 10 ka minuto matag usa).',
    ],
    statement: 'Nabasa nako kini nga sulat, o gibasa kini kanako, ug nasabtan nako kini. Natubag ang akong mga pangutana. Nahibaw-an nako nga mahimo nakong pahunongon ang akong anak bisan kanus-a pinaagi sa pagsulti sa class adviser o sa mga proponent, ug papason dayon ang datos sa akong anak.',
    fieldsCaption: 'Table 2. Detalye sa Bata ug sa Ginikanan o Guardian',
    fields: [
      'Ngalan sa bata', 'Grado ug seksyon', 'Bulan ug tuig sa pagkatawo sa bata (para sa angay nga mga dula)',
      'Unsay angay namong mahibaw-an (pananglitan, sensitibo sa kusog nga tingog)',
      'Ngalan sa ginikanan o guardian ug relasyon sa bata', 'Numero sa kontak',
      'Pirma ug petsa',
    ],
  },
};

function parentPack(lang) {
  const L = PARENT[lang];
  return [
    ...letterhead(),
    heading(L.title),
    plain('{letter_date}', { spacing: { after: 200 } }),
    para(L.salutation, { spacing: { after: 200 } }),
    ...L.paragraphs.map(body),
    subheading(L.whatTitle),
    ...L.what.map(bullet),
    subheading(L.promiseTitle),
    ...L.promise.map(bullet),
    ...L.closingText.map(body),
    para(L.closing, { spacing: { before: 200, after: 0 } }),
    signatures(PROPONENTS),
    ...labelled(lang === 'en' ? 'Noted by:' : 'Gi-noted ni:', ['{principal_name}', '{principal_position}']),
    pageBreak(),
    heading(L.formTitle),
    plain(L.formIntro, { spacing: { after: 160 } }),
    caption(L.tableCaption),
    table(L.cols.slice(0, 1).concat([L.cols[1]]),
      L.items.map((it) => [it, `${L.yes}   ${L.no}`]), [7500, 1860]),
    para(L.statement, { spacing: { before: 200, after: 120 }, alignment: AlignmentType.JUSTIFIED }),
    caption(L.fieldsCaption),
    table(null, L.fields.map((f) => [para(f, { spacing: { after: 0 } }, { bold: true }), '']), [3800, 5560]),
    // Word always ends a document with a paragraph; keep it tiny so a
    // full consent page does not spill onto a blank one.
    new Paragraph({ spacing: { before: 0, after: 0, line: 20, lineRule: 'exact' }, children: [run('', { size: 2 })] }),
  ];
}

function assentScript() {
  return [
    heading('Child Assent Script'),
    body('Read this to each child before every session, in the language the child understands best. Kindergarten and Grade 1 learners cannot sign, so assent is given by word or by action and recorded on Form C. A signed parent consent form is needed first; assent from the child is needed as well, every session.'),
    caption('Table 1. Assent Script in Three Languages'),
    table(['Step', 'English', 'Bisaya', 'Filipino'], [
      ['1', 'Hi, [child\'s name]! I\'m [your name].', 'Hi, [ngalan]! Ako si [imong ngalan].', 'Hi, [pangalan]! Ako si [iyong pangalan].'],
      ['2', 'I have some games on this tablet. Do you want to play with me?', 'Naa koy mga dula diri sa tablet. Gusto ka modula uban nako?', 'May mga laro ako dito sa tablet. Gusto mo bang maglaro kasama ko?'],
      ['3', 'There are no wrong answers. Just do your best.', 'Walay sayop nga tubag. Buhata lang ang imong makaya.', 'Walang maling sagot. Gawin mo lang ang makakaya mo.'],
      ['4', 'If you want to stop, just say "stop" or put the tablet down. That\'s okay.', 'Kung gusto ka mohunong, ingna lang ko og "hunong" o ibutang ang tablet. Okay ra kana.', 'Kung gusto mong tumigil, sabihin mo lang ang "tigil" o ibaba ang tablet. Okay lang iyon.'],
      ['5', 'Do you want to play?', 'Gusto ka modula?', 'Gusto mo bang maglaro?'],
    ], [700, 2886, 2887, 2887]),
    subheading('Signs that the child agrees'),
    bullet('Says yes, nods, smiles, or reaches for the tablet.'),
    subheading('Signs that the child does not agree, or wants to stop'),
    bullet('Says no, shakes the head, turns or walks away, pushes the tablet away, covers the ears or eyes, cries, or looks distressed.'),
    bullet('When any of these appear, do not start, or stop right away. You may offer once more later in the day. Never coax, bribe or insist.'),
    bullet('For a child who does not speak, the observing teacher or SPED teacher judges assent from the child\'s behaviour.'),
    subheading('At the end of every session'),
    bullet('Thank the child by name and give the sticker, whether or not the child finished.'),
    bullet('Record assent, breaks and any early stop on Form C.'),
  ];
}

function forms() {
  return [
    heading('Testing-Day Forms'),
    body('Print enough copies before the testing. Form B is confidential: it is the only place that links a learner\'s name to a code. Keep it in a sealed envelope with the signed consent forms, never photograph it, never type the names into the app, and destroy it after {data_deletion_date}.'),

    subheading('Form A. Testing Schedule'),
    caption('Table 1. Session Schedule'),
    table(['Date', 'Time', 'Learner code', 'Grade and section', 'Session (pre, learning, post)', 'Observer', 'Done'],
      emptyRows(14, 7), [1150, 1000, 1150, 1450, 1810, 1800, 1000]),
    pageBreak(),

    subheading('Form B. Participant Code List (Confidential)'),
    body('Codes are K-01, K-02 and so on for Kindergarten, and G1-01, G1-02 and so on for Grade 1. Enter only the code as the child\'s name in the app. For the birth date, use the first day of the birth month written on the consent form.'),
    caption('Table 2. Participant Codes'),
    table(['Code', 'Learner name', 'Grade and section', 'Consent date', 'Optional items allowed (3 to 6)', 'Withdrawn (date)'],
      emptyRows(16, 6), [900, 2600, 1500, 1300, 1660, 1400]),
    pageBreak(),

    subheading('Form C. Session Record'),
    body('One copy per learner per session. Record what happened, not opinions about the child.'),
    caption('Table 3. Session Record'),
    factTable([
      ['Learner code', ''],
      ['Date', ''],
      ['Session', '☐ Pre-assessment     ☐ Learning session     ☐ Post-assessment'],
      ['Time started / ended', ''],
      ['Tablet number / app version', ''],
      ['Observer', '☐ Class adviser     ☐ SPED teacher     ☐ Parent or guardian     ☐ Other: ________'],
      ['Assent', '☐ Yes, by word     ☐ Yes, by action     ☐ No (session not started)'],
      ['Activities completed', '☐ Learn first     ☐ Copy Me     ☐ Match It     ☐ Do What I Say     ☐ My Turn Your Turn     ☐ Learning activities'],
      ['Sensory settings used', ''],
      ['Number of breaks', ''],
      ['Ended early', '☐ No     ☐ Yes, because:  ☐ child asked   ☐ signs of distress   ☐ tiredness   ☐ technical problem   ☐ class schedule'],
      ['Observer questions answered in the app', '☐ Before     ☐ After'],
      ['Technical problems', [blank(), blank()]],
      ['Notes', [blank(), blank(), blank()]],
    ], 3000),
    signatures([['Proponent', 'Signature over printed name'], ['Observer', 'Signature over printed name']]),
    pageBreak(),

    subheading('Form D. Incident and Withdrawal Log'),
    body('Record any session stopped because of distress, any injury or accident, any complaint, and any withdrawal by a parent or child. Report incidents to the class adviser and the principal on the same day.'),
    caption('Table 4. Incidents and Withdrawals'),
    table(['Date and time', 'Learner code', 'What happened', 'Action taken', 'Reported to', 'Initials'],
      emptyRows(10, 6), [1300, 1100, 2560, 2000, 1400, 1000]),
    pageBreak(),

    subheading('Form E. Attendance Sheet'),
    plain('School: {school_name}          Date: ____________________', { spacing: { after: 120 } }),
    caption('Table 5. Attendance of Teachers, Observers and Proponents'),
    table(['Name', 'Position or role', 'Time in', 'Time out', 'Signature'],
      emptyRows(14, 5), [2800, 2160, 1100, 1100, 2200]),
    pageBreak(),

    subheading('Form F. Testing-Day Checklist'),
    plain('**The day before**', { spacing: { after: 80 } }),
    ...[
      'Tablets fully charged; chargers, extension cord and power bank packed.',
      'App installed and opened once on every tablet, with all game files already loaded for offline play.',
      'A child profile created for each code on Form B, with sensory settings set low (sound, motion).',
      'Volume set low and screen brightness comfortable on every tablet.',
      'Printed copies of Forms A to E, the assent script and the approved principal\'s letter.',
      'Signed consent forms and Form B sealed in an envelope.',
      'Stickers, alcohol or wipes for cleaning tablets, school IDs.',
    ].map(check),
    plain('**At the school**', { spacing: { before: 160, after: 80 } }),
    ...[
      'Sign the school\'s visitor log and report to the principal\'s office.',
      'Confirm the room, the schedule and the observing teacher with the class adviser.',
      'Before each child: check the code on Form B and the consent choices, then read the assent script.',
      'After each child: complete Form C, wipe the tablet, and give the sticker.',
      'Take photos only for learners whose parents allowed it, and never show a face.',
    ].map(check),
    plain('**At the end of the day**', { spacing: { before: 160, after: 80 } }),
    ...[
      'Sync the data when online and make a backup.',
      'Return Form B and the consent forms to the sealed envelope.',
      'Thank the teachers and confirm the next session.',
    ].map(check),
  ];
}

function thanksAndCertification() {
  const certTitle = (s) => para(s, {
    alignment: AlignmentType.CENTER, spacing: { before: 480, after: 360 },
  }, { bold: true, size: 32 });
  return [
    ...letter({
      to: ['{principal_name}', '{principal_position}', '{school_name}', '{school_address}'],
      salutation: 'Dear {principal_salutation}:',
      paragraphs: [
        body('Greetings of peace!'),
        body(`We sincerely thank you for allowing us to conduct the user acceptance testing of our capstone project, **"${TITLE},"** with the Kindergarten and Grade 1 learners of {school_name} on {testing_dates}.`),
        body('We are especially grateful to {kinder_adviser}, {grade1_adviser} and {sped_teacher} for their time, patience and guidance, and to the parents and learners who took part. Your support made the testing possible, and the feedback we received will help us improve the app.'),
        body('As promised, we will send the school a summary of the overall results once our analysis is complete. No individual learner will be identified in it.'),
        body('Thank you once again for your support.'),
      ],
      after: [...labelled('Noted by:', ADVISER)],
    }),
    pageBreak(),

    center('{school_name}', { bold: true }),
    center('{school_address}'),
    certTitle('CERTIFICATION'),
    body(`This is to certify that **Mr. Benedict Paul S. Samson** and **Mr. Ruel Jr. A. Mendio**, Bachelor of Science in Information Technology students of Assumption College of Davao, conducted the user acceptance testing of their capstone project, **"${TITLE},"** with Kindergarten and Grade 1 learners of this school on {testing_dates}.`),
    body('The activity was carried out with the approval of the school administration, with the written consent of the parents or guardians of the participating learners, and in the presence of the school\'s teachers.'),
    body('This certification is issued upon the request of the above-named students for whatever legal purpose it may serve.'),
    plain('Issued this ____ day of ______________, ______.', { spacing: { before: 200 } }),
    ...sigLines(['{principal_name}', '{principal_position}']),
  ];
}

function certificate() {
  const certTitle = (s) => para(s, {
    alignment: AlignmentType.CENTER, spacing: { before: 480, after: 360 },
  }, { bold: true, size: 32 });
  return [
    center('ASSUMPTION COLLEGE OF DAVAO', { bold: true }, { spacing: { before: 240, after: 0 } }),
    center('Faculty of Information Technology'),
    certTitle('CERTIFICATE OF APPRECIATION'),
    center('is given to'),
    para('[NAME]', { alignment: AlignmentType.CENTER, spacing: { before: 240, after: 240 } }, { bold: true, size: 28 }),
    para(`in grateful recognition of valuable support as **[role, for example SPED Teacher and Expert Evaluator]** during the user acceptance testing of the capstone project **"${TITLE},"** conducted at {school_name} on {testing_dates}.`,
      { alignment: AlignmentType.CENTER, spacing: { after: 240 } }),
    center('Given this ____ day of ______________, ______ at {school_name}.'),
    blank(),
    signatures([...PROPONENTS, ADVISER, ['{dean_name}', '{dean_position}']], 12960),
  ];
}

// ------------------------------------------------------------- writing

const NUMBERING = {
  config: [
    { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    ...['advisers', 'sped'].map((reference) => ({
      reference,
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
    })),
  ],
};

const DOCS = [
  ['01_Study_Summary', studySummary, false],
  ['02_Letter_to_Schools_Division_Superintendent', sdsLetter, false],
  ['03_Letter_to_School_Principal', principalLetter, false],
  ['04_Capstone_Adviser_Endorsement', adviserEndorsement, false],
  ['05_Letter_to_Class_Advisers', classAdviserLetter, false],
  ['06_Letter_to_SPED_Teacher', spedLetter, false],
  ['07_Parent_Letter_and_Consent_English', () => parentPack('en'), true],
  ['08_Parent_Letter_and_Consent_Bisaya', () => parentPack('ceb'), true],
  ['09_Child_Assent_Script', assentScript, false],
  ['10_Testing_Day_Forms', forms, true],
  ['11_Thank_You_Letter_and_Certification', thanksAndCertification, false],
  ['12_Certificate_of_Appreciation', certificate, false, true],
];

const pageFooter = () => new Footer({
  children: [new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ children: ['Page ', PageNumber.CURRENT, ' of ', PageNumber.TOTAL_PAGES], font: FONT, size: 20, color: BLACK })],
  })],
});

(async () => {
  for (const [name, build, numberPages, landscape] of DOCS) {
    const doc = new Document({
      creator: 'Aumazing proponents',
      title: name.replace(/^\d+_/, '').replace(/_/g, ' '),
      styles: { default: { document: { run: { font: FONT, size: SIZE, color: BLACK } } } },
      numbering: NUMBERING,
      sections: [{
        properties: { page: { size: landscape ? { width: 12240, height: 15840, orientation: PageOrientation.LANDSCAPE } : { width: 12240, height: 15840 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
        footers: numberPages ? { default: pageFooter() } : undefined,
        children: build(),
      }],
    });
    const file = path.join(OUT_DIR, `${name}.docx`);
    fs.writeFileSync(file, await Packer.toBuffer(doc));
    console.log('wrote', path.relative(process.cwd(), file));
  }
})();
