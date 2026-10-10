// Builds the user acceptance testing kit for Aumazing:
//   1. Aumazing_UAT_Test_Cases.docx    — per-module test case sheets
//   2. Aumazing_UTAUT_Acceptance_Survey.docx — parent/guardian acceptance survey
//
//   NODE_PATH=<dir with the docx npm package> node docs/acceptance-testing/src/build_uat_docs.js
//
// Formatting follows the capstone document standard: Times New Roman 12pt,
// black text, plain 1pt tables, captions above tables.

const fs = require('fs');
const path = require('path');
const {
  AlignmentType, BorderStyle, Document, Packer, Paragraph, ShadingType,
  Table, TableCell, TableRow, TextRun, WidthType,
} = require('docx');

const OUT_DIR = path.join(__dirname, '..');
const FONT = 'Times New Roman';
const SIZE = 24; // half-points: 12pt
const BLACK = '000000';
const CONTENT_WIDTH = 9360; // portrait Letter, 1in margins
const LABEL_W = 2340;
const VALUE_W = CONTENT_WIDTH - LABEL_W;

const run = (text, opts = {}) =>
  new TextRun({ text, font: FONT, size: SIZE, color: BLACK, ...opts });

const plain = (text, opts = {}) => new Paragraph({
  alignment: opts.align,
  spacing: { after: opts.after ?? 80 },
  children: Array.isArray(text) ? text : [run(text)],
});

const body = (text, opts = {}) => new Paragraph({
  alignment: AlignmentType.JUSTIFIED,
  indent: { firstLine: 720 },
  spacing: { after: 120, line: 276 },
  children: Array.isArray(text) ? text : [run(text)],
  ...opts,
});

const heading = (text) => new Paragraph({
  spacing: { before: 280, after: 120 },
  keepNext: true,
  children: [run(text, { bold: true })],
});

const caption = (text) => new Paragraph({
  spacing: { before: 240, after: 80 },
  keepNext: true,
  children: [run(text, { bold: true })],
});

const border = { style: BorderStyle.SINGLE, size: 8, color: BLACK };
const borders = { top: border, bottom: border, left: border, right: border };

function cell(content, width, opts = {}) {
  const items = Array.isArray(content) ? content : [content];
  const paras = items.map((c) =>
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

const stepPar = (text) => new Paragraph({
  spacing: { after: 20 },
  children: [run(text)],
});

const blankLines = (n) => Array.from({ length: n }, () => new Paragraph({
  spacing: { after: 0 },
  children: [run('')],
}));

// ── Test case content ──────────────────────────────────────────────────

const PROJECT = 'Aumazing: A Gamified Learning App for Children with ' +
  'Early Childhood Autism Spectrum Disorder';
const ENVIRONMENT = 'Android release build 1.3.0 (versionCode 5)';

const MODULES = [
  {
    name: 'Login',
    cases: [
      {
        id: 'AUM_Login_001',
        scenario: 'Verify that a registered parent or guardian can sign in with an email and a password.',
        pre: 'A registered account exists; the app shows the Log In screen.',
        steps: [
          '1. In the Email field, type the registered email address.',
          '2. In the Password field, type the account password.',
          '3. Tap Log In.',
        ],
        data: 'Email: parent01@example.com; Password: AuMz@2026',
        expected: 'The parent dashboard opens and shows the child cards (Start here, Enter Child Mode, Recommended Module, Recent Activity). The account stays signed in after closing and reopening the app.',
      },
      {
        id: 'AUM_Login_002',
        scenario: 'Verify that sign-in is blocked when the required fields are empty.',
        pre: 'The app shows the Log In screen.',
        steps: [
          '1. Leave the Email and Password fields empty.',
          '2. Tap Log In.',
        ],
        data: 'Email: (empty); Password: (empty)',
        expected: 'The messages "Please enter your email" and "Please enter your password" appear; the dashboard does not open.',
      },
      {
        id: 'AUM_Login_003',
        scenario: 'Verify that an incorrectly formatted email address is rejected.',
        pre: 'The app shows the Log In screen.',
        steps: [
          '1. In the Email field, type an address without the @ symbol.',
          '2. In the Password field, type any password.',
          '3. Tap Log In.',
        ],
        data: 'Email: parent01.gmail.com; Password: AuMz@2026',
        expected: 'The message "Please enter a valid email" appears; sign-in does not proceed.',
      },
      {
        id: 'AUM_Login_004',
        scenario: 'Verify that a wrong password is rejected.',
        pre: 'A registered account exists; the app shows the Log In screen.',
        steps: [
          '1. In the Email field, type the registered email address.',
          '2. In the Password field, type an incorrect password.',
          '3. Tap Log In.',
        ],
        data: 'Email: parent01@example.com; Password: WrongPass1',
        expected: 'The error message "Invalid login credentials" appears; the dashboard does not open.',
      },
      {
        id: 'AUM_Login_005',
        scenario: 'Verify that a parent can sign in with a Google account.',
        pre: 'The app shows the Log In screen; a Google account is available on the device.',
        steps: [
          '1. Tap Continue with Google.',
          '2. Choose the Google account in the account picker.',
        ],
        data: 'A Google account signed in on the device.',
        expected: 'Sign-in completes and the parent dashboard opens.',
      },
      {
        id: 'AUM_Login_006',
        scenario: 'Verify that a user can continue without an account.',
        pre: 'The app shows the Log In screen.',
        steps: [
          '1. Tap Continue as Guest.',
        ],
        data: 'None.',
        expected: 'The app opens in guest mode and shows the dashboard without requiring an account.',
      },
      {
        id: 'AUM_Login_007',
        scenario: 'Verify that a forgotten password can be reset.',
        pre: 'A registered account exists; the email inbox is reachable.',
        steps: [
          '1. Tap Forgot Password?.',
          '2. Enter the registered email address and submit the request.',
          '3. Follow the reset instructions sent to the email.',
          '4. In New Password and Confirm New Password, type the new password.',
          '5. Tap Update Password.',
        ],
        data: 'Email: parent01@example.com; New Password: N3wPass@2026',
        expected: 'The password is updated and signing in with the new password opens the dashboard.',
      },
      {
        id: 'AUM_Login_008',
        scenario: 'Verify that mismatched new passwords are rejected during reset.',
        pre: 'The password reset screen is open.',
        steps: [
          '1. In New Password, type a new password.',
          '2. In Confirm New Password, type a different password.',
          '3. Tap Update Password.',
        ],
        data: 'New Password: N3wPass@2026; Confirm New Password: N3wPass@2027',
        expected: 'The message "Passwords do not match" appears; the password is not changed.',
      },
    ],
  },
  {
    name: 'Registration',
    cases: [
      {
        id: 'AUM_Register_001',
        scenario: 'Verify that a new parent or guardian can register an account.',
        pre: 'The app shows the Log In screen; the email address is not yet registered.',
        steps: [
          '1. Tap "Don\'t have an account? Register".',
          '2. In Full Name, type your name.',
          '3. In Email, type an email address.',
          '4. In Password, type a password of at least six characters.',
          '5. Open the Data Privacy Notice and tap I Agree.',
          '6. Tap Sign Up.',
          '7. In Verify Your Email, enter the six-digit code sent to the email address.',
        ],
        data: 'Full Name: Juan dela Cruz; Email: juan.delacruz@example.com; Password: AuMz@2026; Code: the six digits from the email',
        expected: 'The account is created, the email is verified, and the child profile setup ("Tell us about your child") opens.',
      },
      {
        id: 'AUM_Register_002',
        scenario: 'Verify that an empty full name is rejected.',
        pre: 'The Sign Up screen is open.',
        steps: [
          '1. Leave Full Name empty and fill in Email and Password.',
          '2. Tap Sign Up.',
        ],
        data: 'Full Name: (empty); Email: juan.delacruz@example.com; Password: AuMz@2026',
        expected: 'The message "Please enter your name" appears; registration does not proceed.',
      },
      {
        id: 'AUM_Register_003',
        scenario: 'Verify that an incorrectly formatted email address is rejected.',
        pre: 'The Sign Up screen is open.',
        steps: [
          '1. In Full Name, type a name.',
          '2. In Email, type an address without the @ symbol.',
          '3. In Password, type a valid password.',
          '4. Tap Sign Up.',
        ],
        data: 'Email: juan.delacruz.example.com',
        expected: 'The message "Please enter a valid email" appears; registration does not proceed.',
      },
      {
        id: 'AUM_Register_004',
        scenario: 'Verify that a password shorter than six characters is rejected.',
        pre: 'The Sign Up screen is open.',
        steps: [
          '1. Fill in Full Name and Email.',
          '2. In Password, type fewer than six characters.',
          '3. Tap Sign Up.',
        ],
        data: 'Password: abc',
        expected: 'The message "At least 6 characters" appears; registration does not proceed.',
      },
      {
        id: 'AUM_Register_005',
        scenario: 'Verify that registration is blocked when the Data Privacy Notice is not accepted.',
        pre: 'The Sign Up screen is open.',
        steps: [
          '1. Fill in Full Name, Email and Password correctly.',
          '2. Leave the Data Privacy Notice unaccepted.',
          '3. Tap Sign Up.',
        ],
        data: 'Full Name: Juan dela Cruz; Email: juan.delacruz@example.com; Password: AuMz@2026',
        expected: 'The message "Please accept the Data Privacy Notice to continue." appears; registration does not proceed.',
      },
      {
        id: 'AUM_Register_006',
        scenario: 'Verify that an incomplete verification code is rejected.',
        pre: 'Registration reached the Verify Your Email screen.',
        steps: [
          '1. Enter only three digits of the six-digit code.',
          '2. Tap Verify Email.',
        ],
        data: 'Code: 123',
        expected: 'The message "Please enter the full 6-digit code." appears; the email is not verified.',
      },
    ],
  },
  {
    name: 'Child Profile Setup',
    cases: [
      {
        id: 'AUM_Profile_001',
        scenario: 'Verify that a caregiver can complete the child profile setup.',
        pre: 'A newly registered account, or Settings then Manage Children with the add-child action.',
        steps: [
          '1. In Child\'s Name, type the child\'s name.',
          '2. Under Gender, select Boy, Girl or Prefer not to say.',
          '3. Open the Birth Date picker and select the birth date.',
          '4. Choose an avatar (for example, Bear).',
          '5. Choose the game screen background.',
          '6. Tap Continue.',
          '7. Set the sound and prompt preferences, then continue.',
          '8. Tap Continue to Dashboard.',
        ],
        data: 'Child\'s Name: K-01; Gender: Boy; Birth Date: 04/21/2022; Avatar: Bear',
        expected: 'The profile is saved, the parent dashboard opens, and the child\'s name appears on the dashboard.',
      },
      {
        id: 'AUM_Profile_002',
        scenario: 'Verify that required child fields cannot be left empty.',
        pre: 'The child profile setup is open at "Tell us about your child".',
        steps: [
          '1. Leave Child\'s Name, Gender and Birth Date empty.',
          '2. Tap Continue.',
        ],
        data: 'All fields empty.',
        expected: 'The messages "Please enter your child\'s name", "Please select your child\'s gender." and "Please select your child\'s birth date." appear.',
      },
      {
        id: 'AUM_Profile_003',
        scenario: 'Verify that a birth date in the future is rejected.',
        pre: 'The child profile setup is open.',
        steps: [
          '1. Open the Birth Date picker.',
          '2. Select a date after today.',
          '3. Tap Continue.',
        ],
        data: 'Birth Date: 12/25/2027',
        expected: 'The message "Birth date cannot be in the future." appears; the date is not accepted.',
      },
      {
        id: 'AUM_Profile_004',
        scenario: 'Verify that the birth date auto-formats and the age is calculated.',
        pre: 'The child profile setup is open.',
        steps: [
          '1. Type 04212022 into the Birth Date field without separators.',
          '2. Observe the field and the calculated age.',
        ],
        data: 'Typed digits: 04212022',
        expected: 'The entry auto-formats as 04/21/2022 and the screen shows the calculated age (4 years old).',
      },
    ],
  },
  {
    name: 'Sensory Preferences',
    cases: [
      {
        id: 'AUM_Sensory_001',
        scenario: 'Verify that per-child sensory preferences can be adjusted and saved.',
        pre: 'A child profile exists; the Sensory Preferences screen or Settings then Child Preferences is open.',
        steps: [
          '1. Turn Background Music on and choose a music style.',
          '2. Adjust the music Volume.',
          '3. Toggle Sound Effects and Vibration.',
          '4. Set Animation Intensity and Prompt Speed.',
          '5. Close and reopen the screen to check the saved values.',
        ],
        data: 'Music: Soft & Relaxing; Volume: 50%; Prompt Speed: Slow',
        expected: 'Each setting is saved and reopens with the chosen values, and the next play session reflects them.',
      },
      {
        id: 'AUM_Sensory_002',
        scenario: 'Verify that every sensory stimulus has a working off state.',
        pre: 'A child profile exists; the sensory preferences are open.',
        steps: [
          '1. Turn Background Music, Sound Effects and Vibration off.',
          '2. Enter Child Mode and play any game.',
        ],
        data: 'All three stimuli set to off.',
        expected: 'No music, sound effect or vibration plays during the game.',
      },
      {
        id: 'AUM_Sensory_003',
        scenario: 'Verify that a parent-built custom music mix plays in child mode.',
        pre: 'Settings is open.',
        steps: [
          '1. Open Settings then Audio.',
          '2. Select Custom Mix (3-5 tracks).',
          '3. Choose three to five tracks.',
          '4. Enter Child Mode and play a game.',
        ],
        data: 'Tracks: any three tracks from the list.',
        expected: 'The chosen custom tracks play as background music during the game.',
      },
    ],
  },
  {
    name: 'Screen Time',
    cases: [
      {
        id: 'AUM_Screentime_001',
        scenario: 'Verify that the daily play limit stops child mode at the set time.',
        pre: 'Settings is open; the caregiver can unlock the parent area.',
        steps: [
          '1. Open Settings then Screen Time.',
          '2. Select Custom daily limit and choose 15 minutes.',
          '3. Enter Child Mode and play until the limit is reached.',
          '4. On the dialog, tap Exit Child Mode.',
        ],
        data: 'Daily Limit: 15 minutes',
        expected: 'The "Screen time is up" dialog appears with "Today\'s play limit has been reached.", offering Add 15 minutes and Exit Child Mode; Exit Child Mode returns to the parent dashboard.',
      },
      {
        id: 'AUM_Screentime_002',
        scenario: 'Verify that the per-session limit ends a single play session.',
        pre: 'Settings is open.',
        steps: [
          '1. Open Settings then Screen Time.',
          '2. Select Custom session limit and choose 5 minutes.',
          '3. Enter Child Mode and play one game for five minutes.',
        ],
        data: 'Session Limit: 5 minutes',
        expected: 'The message "This play session has reached its limit." appears at the end of the session.',
      },
      {
        id: 'AUM_Screentime_003',
        scenario: 'Verify that no time-up dialog appears when no limit is set.',
        pre: 'Settings is open.',
        steps: [
          '1. Open Settings then Screen Time.',
          '2. Select No daily limit and No session limit.',
          '3. Enter Child Mode and play for an extended period.',
        ],
        data: 'Daily Limit: No daily limit; Session Limit: No session limit',
        expected: 'No time-up dialog appears during the extended session.',
      },
    ],
  },
  {
    name: 'Pre-Assessment',
    cases: [
      {
        id: 'AUM_Assess_001',
        scenario: 'Verify that a caregiver can start the gamified pre-assessment.',
        pre: 'A child profile with no prior assessment; the parent dashboard is open.',
        steps: [
          '1. On the Start here card, tap Start Pre-Assessment.',
          '2. Read "Let\'s Get to Know You!" and tap Let\'s Start!.',
          '3. On the "Before you begin" dialog, tap I understand.',
          '4. Complete the four assessment games: Copy Me, Do What I Say, My Turn, Your Turn and Match It.',
        ],
        data: 'A child profile with no prior assessment cycle.',
        expected: 'All four assessment games run in order and the flow ends without errors.',
      },
      {
        id: 'AUM_Assess_002',
        scenario: 'Verify that the assessment produces a summary and recommendations.',
        pre: 'The fourth assessment game has just been completed.',
        steps: [
          '1. Open the Assessment Summary.',
          '2. Review each section, then tap Go to My Path.',
        ],
        data: 'A completed four-game assessment run.',
        expected: 'The Assessment Summary shows Overall Performance, Game Results, a Developmental Profile across Communication, Social Interaction, Play Skills and Attention & Focus, and Recommended Activities; Go to My Path opens the recommended learning path.',
      },
      {
        id: 'AUM_Assess_003',
        scenario: 'Verify that a full assessment can complete offline and syncs later.',
        pre: 'The device is in airplane mode; a child profile with no prior assessment.',
        steps: [
          '1. Turn on airplane mode.',
          '2. Start and complete a full pre-assessment cycle.',
          '3. Check the sync banner on the dashboard.',
          '4. Turn airplane mode off and wait on the dashboard.',
        ],
        data: 'Connectivity: none during the run; restored afterwards.',
        expected: 'The assessment completes and the summary is produced on the device; the banner shows "Offline - N changes saved on this device" and then "All synced" after reconnecting, with no lost or duplicated results.',
      },
      {
        id: 'AUM_Assess_004',
        scenario: 'Verify that the free tier locks the fresh recommendation after one cycle.',
        pre: 'Free plan; the child already has one completed assessment cycle.',
        steps: [
          '1. On the dashboard, start and complete another assessment cycle.',
          '2. Return to the dashboard and review the recommendation card.',
        ],
        data: 'Plan: Free plan; completed cycles: 2.',
        expected: 'The card shows "Fresh Recommendation Locked" with "Subscribe to Premium to unlock a fresh personalized learning path after every assessment." and an Unlock button.',
      },
    ],
  },
  {
    name: 'Child Mode and Learning Activities',
    cases: [
      {
        id: 'AUM_Game_001',
        scenario: 'Verify that a child can complete a learning activity and earn a star.',
        pre: 'A child profile exists; the parent dashboard is open.',
        steps: [
          '1. Tap Enter Child Mode ("Hand device to child").',
          '2. In the child lobby, open All Games and choose Match It.',
          '3. Set the difficulty to Easy and complete the game.',
          '4. Tap Finish on the reward screen.',
        ],
        data: 'Game: Match It; Difficulty: Easy.',
        expected: 'The activity runs and accepts responses; "You completed the game!" appears with the stars earned; Finish returns to the child lobby.',
      },
      {
        id: 'AUM_Game_002',
        scenario: 'Verify the turn-taking pacing in My Turn, Your Turn.',
        pre: 'Child Mode is open at All Games.',
        steps: [
          '1. Choose My Turn, Your Turn on Easy.',
          '2. Watch the demonstration and the hand-off to the child\'s turn.',
        ],
        data: 'Game: My Turn, Your Turn; Difficulty: Easy.',
        expected: 'The turn advances only after the demonstration and the wait interval complete, giving the child time to respond.',
      },
      {
        id: 'AUM_Game_003',
        scenario: 'Verify that the Copy Me demonstration holds to completion on easy difficulty.',
        pre: 'Child Mode is open at All Games.',
        steps: [
          '1. Choose Copy Me on Easy.',
          '2. Watch the demonstration sequence.',
        ],
        data: 'Game: Copy Me; Difficulty: Easy.',
        expected: 'The demonstration sequence is held to completion (about three seconds) before the child\'s turn is offered.',
      },
      {
        id: 'AUM_Game_004',
        scenario: 'Verify that a child can retry after an incorrect response.',
        pre: 'Child Mode is open at any game.',
        steps: [
          '1. Respond incorrectly on purpose.',
          '2. Follow the on-screen prompt to try again.',
        ],
        data: 'Any game; an intentionally wrong response.',
        expected: 'The child is prompted to try again (Again or Try again) and can retry without leaving the activity.',
      },
      {
        id: 'AUM_Game_005',
        scenario: 'Verify that earned stars unlock and apply a costume.',
        pre: 'The account has at least one star.',
        steps: [
          '1. Open Settings then Stars & Costumes.',
          '2. Open My Costumes and wear an unlocked costume.',
          '3. Enter Child Mode and observe the buddy.',
        ],
        data: 'An unlocked costume from the Star Shop.',
        expected: 'The chosen costume appears on the child\'s buddy in child mode.',
      },
      {
        id: 'AUM_Game_006',
        scenario: 'Verify that every learning activity in the library opens and runs.',
        pre: 'Child Mode is open at All Games.',
        steps: [
          '1. Open each game in the list once.',
          '2. Interact with one trial in each, then exit.',
        ],
        data: 'Games: Match It; Copy Me; Do What I Say; My Turn, Your Turn; Sari-Sari Store Sorting; Trace It; Tulong, Kaibigan!; Hintay!; Ano\'ng Susunod?; Sabay Tayo!; Kumusta!; Ano\'ng Nararamdaman?',
        expected: 'All twelve games open, respond to touch, and can be exited without freezing.',
      },
    ],
  },
  {
    name: 'Parent Dashboard',
    cases: [
      {
        id: 'AUM_Dash_001',
        scenario: 'Verify that all parent dashboard sections are present.',
        pre: 'The parent is signed in and the dashboard is open.',
        steps: [
          '1. Scroll through the dashboard.',
          '2. Review each card and section.',
        ],
        data: 'An account with at least one child profile.',
        expected: 'The dashboard shows Start here, Enter Child Mode, Therapy Directory, History & Progress, Aumazing Premium, today\'s screen time, Recommended Module, Skills Snapshot, Recent Activity and Sign Out.',
      },
      {
        id: 'AUM_Dash_002',
        scenario: 'Verify that the first-time guided tour presents every dashboard feature.',
        pre: 'A newly registered account opening the dashboard for the first time.',
        steps: [
          '1. Step through the guided tour from Welcome.',
          '2. Advance through each spotlight.',
        ],
        data: 'A first-time account.',
        expected: 'The tour presents Start here, Your child, Sync status, Child mode, Coming back, Settings and Sign out, and ends with "That\'s it"; it can be dismissed.',
      },
      {
        id: 'AUM_Dash_003',
        scenario: 'Verify that history and progress views render recorded sessions.',
        pre: 'The child has at least one completed session.',
        steps: [
          '1. Tap History & Progress.',
          '2. Open Overall summary and Advanced trends.',
        ],
        data: 'At least one completed game session for the child.',
        expected: 'Past sessions and progress charts render without errors.',
      },
      {
        id: 'AUM_Dash_004',
        scenario: 'Verify that parent-facing labels remain readable under enlarged text.',
        pre: 'The device display settings are reachable.',
        steps: [
          '1. In the device settings, set the font size to the largest scale (about 1.3x).',
          '2. Reopen the parent dashboard.',
        ],
        data: 'Device font scale: 1.3x.',
        expected: 'No parent-facing button label is clipped or replaced by ellipses at 1.3x text scale.',
      },
    ],
  },
  {
    name: 'Therapy Directory',
    cases: [
      {
        id: 'AUM_Therapy_001',
        scenario: 'Verify that a premium parent can find centres near them and open directions.',
        pre: 'Premium entitlement active; location permission granted.',
        steps: [
          '1. On the dashboard, tap Therapy Directory ("Centers near you").',
          '2. Tap Find near me.',
          '3. Open a centre from the list.',
          '4. Tap Directions.',
        ],
        data: 'Device location within Davao City.',
        expected: 'Centres are listed nearest first with their details, and Directions hands off to the device map application.',
      },
      {
        id: 'AUM_Therapy_002',
        scenario: 'Verify that the free tier shows only the city-level directory.',
        pre: 'The account is on the Free plan.',
        steps: [
          '1. On the dashboard, tap Therapy Directory.',
          '2. Try to open a centre\'s details.',
        ],
        data: 'Plan: Free plan.',
        expected: 'The free tier shows the city-level directory with "Premium unlocks details"; Unlock locator leads to the upgrade screen.',
      },
    ],
  },
  {
    name: 'Premium and Subscription',
    cases: [
      {
        id: 'AUM_Premium_001',
        scenario: 'Verify that a parent can upgrade to Premium through the checkout.',
        pre: 'The parent dashboard is open on the Free plan.',
        steps: [
          '1. On the Aumazing Premium card, tap Upgrade.',
          '2. Review the price line: 149 pesos for 30 days, one-time payment, never renews by itself.',
          '3. Tap Upgrade with PayMongo.',
          '4. Pay with a sandbox test card.',
        ],
        data: 'A PayMongo sandbox test card; environment: provider sandbox, no real charge.',
        expected: 'The payment completes, the message "Welcome to Premium!" appears, and the plan shows as Premium.',
      },
      {
        id: 'AUM_Premium_002',
        scenario: 'Verify that the Premium entitlement unlocks the gated features.',
        pre: 'The account has just upgraded to Premium.',
        steps: [
          '1. Complete a new assessment cycle for the child.',
          '2. Return to the dashboard and review the recommendation card.',
          '3. Open Therapy Directory and open a centre\'s details.',
        ],
        data: 'Plan: Premium; a new completed assessment cycle.',
        expected: 'The fresh recommendation is unlocked after the new cycle and the centre details are visible in the directory.',
      },
      {
        id: 'AUM_Premium_003',
        scenario: 'Verify that cancelling the checkout does not grant the entitlement.',
        pre: 'The premium upgrade screen is open.',
        steps: [
          '1. Tap Upgrade with PayMongo.',
          '2. Close or cancel the checkout before paying.',
        ],
        data: 'Checkout cancelled before payment.',
        expected: 'The app returns to the upgrade screen; the plan remains Free plan and no charge is made.',
      },
    ],
  },
  {
    name: 'Offline and Synchronization',
    cases: [
      {
        id: 'AUM_Offline_001',
        scenario: 'Verify that the app offers guest access while offline.',
        pre: 'The device is in airplane mode; the app is not signed in.',
        steps: [
          '1. Open the app.',
          '2. Read the banner on the Log In screen.',
          '3. Tap Continue as Guest.',
        ],
        data: 'Connectivity: none.',
        expected: 'The banner "You\'re offline - you can continue as Guest and sign in later." appears and guest mode opens.',
      },
      {
        id: 'AUM_Offline_002',
        scenario: 'Verify that offline gameplay is stored locally and syncs without loss or duplication.',
        pre: 'The parent is signed in; the device is in airplane mode.',
        steps: [
          '1. Enter Child Mode and complete one game.',
          '2. Return to the dashboard and check the sync banner.',
          '3. Turn airplane mode off and wait on the dashboard.',
          '4. Open Recent Activity.',
        ],
        data: 'Connectivity: none during play, restored afterwards.',
        expected: 'The banner shows "Offline - N changes saved on this device", then "Syncing N..." and finally "All synced"; the session appears in Recent Activity exactly once.',
      },
    ],
  },
];

// ── Document 1: UAT test cases ─────────────────────────────────────────

function moduleHeaderTable(moduleName) {
  const rows = [
    ['Project Name', PROJECT],
    ['Module Name', moduleName],
    ['Environment', ENVIRONMENT],
    ['Created By', ''],
  ];
  return new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [LABEL_W, VALUE_W],
    rows: rows.map(([label, value]) => new TableRow({
      cantSplit: true,
      children: [
        cell(label, LABEL_W, { bold: true }),
        cell(value === '' ? blankLines(1) : value, VALUE_W),
      ],
    })),
  });
}

function testCaseTable(tc) {
  const rows = [
    ['Test Case ID', tc.id],
    ['Test Scenario', tc.scenario],
    ['Pre-Condition', tc.pre],
    ['Procedures', tc.steps.map(stepPar)],
    ['Test Data', tc.data],
    ['Expected Result', tc.expected],
    ['Actual Result', blankLines(2)],
    ['Status', [plain('☐ Pass          ☐ Fail', { after: 0 })]],
  ];
  return new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [LABEL_W, VALUE_W],
    rows: rows.map(([label, value]) => new TableRow({
      cantSplit: false,
      children: [
        cell(label, LABEL_W, { bold: true }),
        cell(value, VALUE_W),
      ],
    })),
  });
}

function buildUatDoc() {
  const children = [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 60 },
      children: [run('User Acceptance Testing (UAT)', { bold: true, size: 28 })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 240 },
      children: [run('Test Case Document', { size: 26 })],
    }),
    body('This document organizes the user acceptance testing of the Aumazing ' +
      'application by module. Each module sheet begins with an identification ' +
      'table and lists the test cases for that module. Test cases cover both ' +
      'valid inputs (happy path) and invalid inputs (negative scenarios), as ' +
      'well as the interactive features the child and the caregiver use.'),
    body('For each test case, the tester follows the numbered procedures, ' +
      'enters the listed test data where applicable, and records what actually ' +
      'happened under Actual Result together with a Status of Pass or Fail. ' +
      'A failed test case is reported to the proponents, corrected, and then ' +
      'retested before the module is accepted.'),
  ];

  MODULES.forEach((mod, i) => {
    children.push(new Paragraph({
      spacing: { before: 360, after: 120 },
      keepNext: true,
      children: [run(`Module ${i + 1}: ${mod.name}`, { bold: true, size: 26 })],
    }));
    children.push(moduleHeaderTable(mod.name));
    mod.cases.forEach((tc) => {
      children.push(caption(tc.id));
      children.push(testCaseTable(tc));
    });
  });

  children.push(heading('Testing Summary'));
  children.push(plain('To be completed after all module test cases have been executed.'));
  children.push(new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: [LABEL_W, VALUE_W],
    rows: [
      ['Total test cases executed', ''],
      ['Passed', ''],
      ['Failed', ''],
      ['Pass rate', ''],
    ].map(([label, value]) => new TableRow({
      cantSplit: true,
      children: [
        cell(label, LABEL_W, { bold: true }),
        cell(blankLines(1), VALUE_W),
      ],
    })),
  }));
  children.push(plain(' ', { after: 40 }));
  children.push(plain('Tested by: ______________________________          Date: __________________'));

  return new Document({
    creator: 'Aumazing Proponents',
    title: 'Aumazing User Acceptance Testing - Test Case Document',
    styles: {
      default: {
        document: { run: { font: FONT, size: SIZE, color: BLACK } },
      },
    },
    sections: [{
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 },
        },
      },
      children,
    }],
  });
}

// ── Document 2: UTAUT acceptance survey ────────────────────────────────

const SCALE_ROWS = [
  ['5', 'Strongly Agree', 'You entirely agree with the statement.'],
  ['4', 'Agree', 'You agree for the most part of the statement.'],
  ['3', 'Neither', 'You do not know how you feel about the statement or you do not have enough knowledge to form an opinion about the statement.'],
  ['2', 'Disagree', 'You disagree with the statement for the most part.'],
  ['1', 'Strongly Disagree', 'You entirely disagree with the statement.'],
];

const CONSTRUCTS = [
  {
    title: 'Performance Expectancy (PE)',
    items: [
      'I find Aumazing useful in supporting my child\'s learning.',
      'Using Aumazing helps in developing my child\'s skills.',
      'Using Aumazing makes me able to be aware of my child\'s progress.',
    ],
  },
  {
    title: 'Effort Expectancy (EE)',
    items: [
      'Learning how to use Aumazing is easy for me.',
      'My interaction with Aumazing is clear and understandable.',
      'I find Aumazing to be user-friendly.',
      'Overall, I find Aumazing easy to use.',
    ],
  },
  {
    title: 'Social Influence (SI)',
    items: [
      'People who are important to me think that I should use Aumazing.',
      'People who influence my behavior think that I should use Aumazing.',
      'I would use Aumazing if my friends and fellow parents used it.',
      'Overall, the people important to me support the use of Aumazing.',
    ],
  },
  {
    title: 'Facilitating Conditions (FC)',
    items: [
      'I have the resources necessary to use Aumazing.',
      'I have the knowledge necessary to use Aumazing.',
      'Aumazing is compatible with other technologies I use.',
      'I can get help from others when I have difficulties using Aumazing.',
    ],
  },
  {
    title: 'Behavioral Intention (BI)',
    items: [
      'I intend to use Aumazing in the months to come.',
      'I predict I would use Aumazing in the months to come.',
      'I plan to use Aumazing in the months to come.',
      'In general, I plan to use Aumazing always.',
    ],
  },
];

const RATING_WIDTHS = [5760, 720, 720, 720, 720, 720];

function ratingTable(items) {
  return new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: RATING_WIDTHS,
    rows: [
      new TableRow({
        tableHeader: true,
        children: [
          cell('Statement', RATING_WIDTHS[0], { bold: true, center: true }),
          ...[5, 4, 3, 2, 1].map((n) =>
            cell(String(n), 720, { bold: true, center: true })),
        ],
      }),
      ...items.map((text) => new TableRow({
        cantSplit: true,
        children: [
          cell(text, RATING_WIDTHS[0]),
          ...Array.from({ length: 5 }, () => cell('', 720)),
        ],
      })),
    ],
  });
}

function buildSurveyDoc() {
  const children = [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 240 },
      children: [run('Survey Questionnaire', { bold: true, size: 28 })],
    }),
    body('Dear Respondent,'),
    body('This survey questionnaire is structured to gather your viewpoints on ' +
      'the acceptability and use of the developed Aumazing application, a ' +
      'gamified learning application for young children with early ' +
      'characteristics of Autism Spectrum Disorder. We would be very grateful ' +
      'if you could complete the questionnaire; it should only take several ' +
      'minutes of your time. Rest assured that all information you provide ' +
      'will be treated with utmost confidentiality and will be used for this ' +
      'capstone project only.'),
    body('Thank you very much.'),
    heading('Part I. Profile of the Respondent'),
    plain([
      run('Name: '),
      run('________________________________________________________'),
    ]),
    plain([
      run('Gender:   '),
      run('☐ Male     '),
      run('☐ Female'),
    ]),
    plain([
      run('Age:  ____________'),
    ]),
    plain('Highest Educational Attainment:'),
    plain('       ☐ High School level          ☐ High School graduate'),
    plain('       ☐ Senior High School graduate'),
    plain('       ☐ College level               ☐ College graduate'),
    plain('       ☐ Post-graduate'),
    plain('Relationship to the child:'),
    plain('       ☐ Mother     ☐ Father     ☐ Legal guardian     ☐ Other: ______________'),
    heading('Part II. Acceptability of Aumazing'),
    plain('Please put a check mark on the box that corresponds to your answer.'),
    new Table({
      width: { size: CONTENT_WIDTH, type: WidthType.DXA },
      columnWidths: [1560, 2600, 5200],
      rows: [
        new TableRow({
          tableHeader: true,
          children: [
            cell('Rating Score', 1560, { bold: true, center: true }),
            cell('Categorical Rating', 2600, { bold: true, center: true }),
            cell('Verbal Description', 5200, { bold: true, center: true }),
          ],
        }),
        ...SCALE_ROWS.map(([score, rating, desc]) => new TableRow({
          cantSplit: true,
          children: [
            cell(score, 1560, { center: true }),
            cell(rating, 2600),
            cell(desc, 5200),
          ],
        })),
      ],
    }),
  ];

  CONSTRUCTS.forEach((c) => {
    children.push(caption(c.title));
    children.push(ratingTable(c.items));
  });

  children.push(plain(' ', { after: 120 }));
  children.push(plain('Thank you for your time.', { align: AlignmentType.CENTER }));

  return new Document({
    creator: 'Aumazing Proponents',
    title: 'Aumazing UTAUT Acceptance Survey',
    styles: {
      default: {
        document: { run: { font: FONT, size: SIZE, color: BLACK } },
      },
    },
    sections: [{
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 },
        },
      },
      children,
    }],
  });
}

// ── Write both files ───────────────────────────────────────────────────

(async () => {
  const uat = await Packer.toBuffer(buildUatDoc());
  const uatPath = path.join(OUT_DIR, 'Aumazing_UAT_Test_Cases.docx');
  fs.writeFileSync(uatPath, uat);
  console.log('wrote', uatPath, `(${uat.length} bytes)`);

  const survey = await Packer.toBuffer(buildSurveyDoc());
  const surveyPath = path.join(OUT_DIR, 'Aumazing_UTAUT_Acceptance_Survey.docx');
  fs.writeFileSync(surveyPath, survey);
  console.log('wrote', surveyPath, `(${survey.length} bytes)`);
})();
