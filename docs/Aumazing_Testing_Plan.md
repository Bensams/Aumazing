# Aumazing Testing Plan

## Table 1: Aumazing Functional, Integration, and UAT Testing Plan

| Test Case ID | Test Case Name | Testing Resource | Testing Approach | Test Schedule | Risk and Issues |
|--------------|----------------|------------------|------------------|---------------|-----------------|
| TC-AU-001 | Anonymous Sign-Up & Guest Mode | Ruel Mendio | Functional Testing + UAT: User Registration Flow | August 2026 | **Risk:** Guest data migration to permanent account. **Issue:** Token persistence across sessions |
| TC-AU-002 | Email/Password Authentication | Ruel Mendio | Functional Testing + UAT: Login/Registration | August 2026 | **Risk:** Password validation bypass. **Issue:** Session timeout handling |
| TC-AU-003 | Child Profile Creation | Ruel Mendio | Functional Testing + UAT: Profile Setup | August 2026 | **Risk:** Birth date policy violations. **Issue:** Multiple child profile management |
| TC-AU-004 | Pre-Assessment Flow | Ruel Mendio | Functional Testing + UAT: Assessment Wizard | August 2026 | **Risk:** Assessment data loss on interruption. **Issue:** Progress restoration |
| TC-AU-005 | Sensory Preferences Configuration | Ruel Mendio | Functional Testing + UAT: Settings Management | August 2026 | **Risk:** Incompatible sensory combinations. **Issue:** Voice/animation conflicts |
| TC-AU-006 | Copy Me Game | Ruel Mendio | Functional Testing + UAT: Game Mechanics | August 2026 | **Risk:** Gesture detection failure. **Issue:** Device compatibility |
| TC-AU-007 | Match It Game | Ruel Mendio | Functional Testing + UAT: Game Mechanics | August 2026 | **Risk:** Audio sync issues. **Issue:** Card matching logic errors |
| TC-AU-008 | Do What I Say Game | Ruel Mendio | Functional Testing + UAT: Game Mechanics | August 2026 | **Risk:** Instruction clarity issues. **Issue:** Command parsing errors |
| TC-AU-009 | My Turn Your Turn Game | Ruel Mendio | Functional Testing + UAT: Turn-Based Logic | August 2026 | **Risk:** Turn state management. **Issue:** Delay timing accuracy |
| TC-AU-010 | Game Flow Sequence | Ruel Mendio | Integration Testing + UAT: Multi-Game Flow | August 2026 | **Risk:** Memory leak between games. **Issue:** Reward overlay persistence |
| TC-AU-011 | Reward System | Ruel Mendio | Functional Testing + UAT: Rewards Display | August 2026 | **Risk:** Reward calculation errors. **Issue:** Sticker unlock logic |
| TC-AU-012 | Assessment Dashboard | Ruel Mendio | Functional Testing + UAT: Results Display | August 2026 | **Risk:** Profile scoring accuracy. **Issue:** AI prediction display |
| TC-AU-013 | Offline-First Data Sync | Benedict Paul Samson | Integration Testing + UAT: Sync Mechanism | August 2026 | **Risk:** Data conflict resolution. **Issue:** Network state detection |
| TC-AU-014 | Local Database Operations | Benedict Paul Samson | Integration Testing: SQLite Operations | August 2026 | **Risk:** Database corruption. **Issue:** Migration handling |
| TC-AU-015 | AI Assessment Scoring | Benedict Paul Samson | Integration Testing: XGBoost Scoring | August 2026 | **Risk:** Model loading failure. **Issue:** Score interpretation |
| TC-AU-016 | Rubric-Based Scoring | Benedict Paul Samson | Unit + Integration Testing: Scoring Service | August 2026 | **Risk:** Edge case handling. **Issue:** Weight calculation errors |
| TC-AU-017 | Audio Service Integration | Benedict Paul Samson | Integration Testing: Background Music | August 2026 | **Risk:** Audio resource leaks. **Issue:** Music state persistence |
| TC-AU-018 | Voice Over System | Benedict Paul Samson | Functional Testing + UAT: TTS Integration | August 2026 | **Risk:** Voice overlapping. **Issue:** Composite voice queue |
| TC-AU-019 | OTP Verification | Benedict Paul Samson | Integration Testing: SMS/Email OTP | August 2026 | **Risk:** OTP expiration handling. **Issue:** Resend logic |
| TC-AU-020 | Password Reset Flow | Ruel Mendio | Functional Testing + UAT: Reset Workflow | August 2026 | **Risk:** Token security. **Issue:** Expired link handling |
| TC-AU-021 | Home Screen Navigation | Parent/Guardian Testers | UAT: Navigation Flow | September 2026 | **Risk:** Deep linking failures. **Issue:** State restoration |
| TC-AU-022 | Parent Waiting Screen | Parent/Guardian Testers | UAT: Multi-User Flow | September 2026 | **Risk:** Session hijacking. **Issue:** Timeout handling |
| TC-AU-023 | Game Summary Dialog | Parent/Guardian Testers | UAT: Results Display | September 2026 | **Risk:** Data accuracy. **Issue:** Animation performance |
| TC-AU-024 | Loading Screen | Parent/Guardian Testers | UAT: Initialization Flow | September 2026 | **Risk:** Resource preloading failure. **Issue:** Timeout handling |
| TC-AU-025 | Supabase Integration | Benedict Paul Samson | Integration Testing: Backend API | August 2026 | **Risk:** API rate limiting. **Issue:** Connection timeout |
| TC-AU-026 | Child Profile Policy | Ruel Mendio | Unit + Integration Testing: Validation | August 2026 | **Risk:** Policy bypass. **Issue:** Date boundary cases |
| TC-AU-027 | Cross-Platform Compatibility | Parent/Guardian Testers | UAT: Device/Platform Testing | September 2026 | **Risk:** Screen size adaptation. **Issue:** OS version compatibility |
| TC-AU-028 | Accessibility Features | SPED/SNeD Teacher | UAT: Accessibility Compliance | September 2026 | **Risk:** Screen reader compatibility. **Issue:** Color contrast |
| TC-AU-029 | Data Privacy Compliance | Adviser / IT Evaluator | Security Testing: Data Handling | September 2026 | **Risk:** Data leakage. **Issue:** Local storage encryption |
| TC-AU-030 | Performance Under Load | Benedict Paul Samson | Performance Testing: Resource Usage | August 2026 | **Risk:** Memory exhaustion. **Issue:** Frame rate drops |

---

## Test Case Details

---

### TEST CASE ID: TC-AU-001
**Test Case Name:** Anonymous Sign-Up & Guest Mode

| Field | Details |
|-------|---------|
| **Test Scenario** | Allow the user to use the app without permanent account and later bind to permanent account |
| **Pre-Conditions** | App installed, No existing guest session |
| **Test Steps** | 1. Open the app<br>2. Tap "Continue as Guest"<br>3. Enter child nickname<br>4. Complete child profile setup<br>5. Use app features (games, assessment)<br>6. Navigate to bind account<br>7. Enter email/password<br>8. Complete binding flow |
| **Expected Results** | Guest user created in Supabase<br>Child profile stored locally and synced<br>All guest data preserved after binding<br>User redirected to home screen<br>Refresh token updated to permanent |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-002
**Test Case Name:** Email/Password Authentication

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify user can register and login with email/password |
| **Pre-Conditions** | App installed, Valid email not registered |
| **Test Steps** | 1. Open the app<br>2. Tap "Sign Up"<br>3. Enter valid email<br>4. Enter password (8+ chars)<br>5. Confirm password<br>6. Tap submit<br>7. Verify OTP if required<br>8. Login with credentials<br>9. Verify session persistence |
| **Expected Results** | Account created in Supabase Auth<br>Session token stored securely<br>User redirected to child profile setup<br>Auto-login on app restart<br>Session timeout handled gracefully |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-003
**Test Case Name:** Child Profile Creation

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify child profile creation with birth date validation |
| **Pre-Conditions** | User authenticated (guest or permanent) |
| **Test Steps** | 1. Complete auth flow<br>2. Enter child's full name<br>3. Select birth date<br>4. Select gender<br>5. Enter nickname (optional)<br>6. Tap continue<br>7. Verify profile stored<br>8. Test birth date boundaries (too young/too old) |
| **Expected Results** | Profile validated against birth date policy (3-12 years)<br>Profile stored in local DB<br>Profile synced to Supabase if authenticated<br>Error shown for invalid dates<br>Multiple profiles can be created |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-004
**Test Case Name:** Pre-Assessment Flow

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify complete pre-assessment wizard with progress tracking |
| **Pre-Conditions** | Child profile created |
| **Test Steps** | 1. Navigate to assessment<br>2. Complete intro screen<br>3. Progress through all questions<br>4. Answer each item<br>5. Submit responses<br>6. Verify results calculation<br>7. Test interruption/resumption<br>8. Test retake functionality |
| **Expected Results** | All assessment items displayed correctly<br>Progress saved at each step<br>Results calculated accurately<br>Profile generated based on responses<br>Progress restored after interruption<br>Can retake assessment from dashboard |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-005
**Test Case Name:** Sensory Preferences Configuration

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify sensory settings customization and persistence |
| **Pre-Conditions** | Child profile created |
| **Test Steps** | 1. Navigate to sensory preferences<br>2. Toggle voice over<br>3. Select voice type<br>4. Toggle animations<br>5. Adjust other sensory settings<br>6. Save preferences<br>7. Restart app<br>8. Verify settings persisted<br>9. Test incompatible combinations |
| **Expected Results** | All sensory options toggle correctly<br>Voice over plays with selected voice<br>Animation settings applied immediately<br>Preferences stored in local DB<br>Settings survive app restart<br>Conflicting options handled gracefully |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-006
**Test Case Name:** Copy Me Game

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify Copy Me game mechanics and scoring |
| **Pre-Conditions** | Child profile with assessment completed |
| **Test Steps** | 1. Launch Copy Me game<br>2. Follow on-screen gestures<br>3. Complete sequence correctly<br>4. Verify scoring feedback<br>5. Test incorrect responses<br>6. Test hint system<br>7. Complete full game session<br>8. Verify reward trigger |
| **Expected Results** | Gestures detected accurately<br>Correct responses scored<br>Incorrect responses handled<br>Hints display appropriately<br>Voice instructions clear<br>Visual feedback provided<br>Reward shown on completion<br>Score recorded in database |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-007
**Test Case Name:** Match It Game

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify Match It game card matching and audio feedback |
| **Pre-Conditions** | Child profile created |
| **Test Steps** | 1. Launch Match It game<br>2. Tap cards to flip<br>3. Match correct pairs<br>4. Verify match animation<br>5. Test non-matching pairs<br>6. Verify audio feedback<br>7. Complete all matches<br>8. Verify game completion |
| **Expected Results** | Cards flip with animation<br>Matching pairs stay revealed<br>Non-matches flip back<br>Audio plays on match/mismatch<br>Game completes when all matched<br>Score calculated correctly<br>Reward displayed |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-008
**Test Case Name:** Do What I Say Game

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify command following and instruction clarity |
| **Pre-Conditions** | Child profile created |
| **Test Steps** | 1. Launch Do What I Say game<br>2. Listen to voice instruction<br>3. Perform correct action<br>4. Verify success feedback<br>5. Test incorrect action<br>6. Verify retry mechanism<br>7. Progress through levels<br>8. Complete game session |
| **Expected Results** | Voice instructions clear and audible<br>Commands parsed correctly<br>Correct actions rewarded<br>Incorrect actions allow retry<br>Progress tracked across levels<br>Scoring accurate<br>Game completes successfully |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-009
**Test Case Name:** My Turn Your Turn Game

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify turn-based interaction and timing |
| **Pre-Conditions** | Child profile created |
| **Test Steps** | 1. Launch My Turn Your Turn game<br>2. Observe "My Turn" demonstration<br>3. Wait for "Your Turn" cue<br>4. Perform action in turn<br>5. Verify turn indicators<br>6. Test timing accuracy<br>7. Complete multiple turns<br>8. Finish game session |
| **Expected Results** | Turn indicators clear (visual/auditory)<br>"My Turn" demonstration plays<br>"Your Turn" cue triggers correctly<br>User input accepted during turn<br>Timing delays accurate<br>State management correct<br>Game completion handled |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-010
**Test Case Name:** Game Flow Sequence

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify multi-game flow with rewards between games |
| **Pre-Conditions** | Child profile with sensory settings configured |
| **Test Steps** | 1. Start Practice Flow (4 games)<br>2. Complete Copy Me<br>3. Verify reward overlay<br>4. Continue to Match It<br>5. Complete game<br>6. Verify reward<br>7. Continue through all games<br>8. Verify final completion<br>9. Test early exit |
| **Expected Results** | Games launch in correct sequence<br>Reward overlay shows after each game<br>"Next Game" button proceeds<br>"Finish" button on last game<br>Home screen reached on complete<br>Progress saved at each step<br>Early exit preserves progress |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-011
**Test Case Name:** Reward System

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify reward calculation and sticker unlocks |
| **Pre-Conditions** | Games completed with scores |
| **Test Steps** | 1. Complete game with high score<br>2. Verify reward calculation<br>3. Check sticker unlocks<br>4. View rewards collection<br>5. Complete multiple games<br>6. Verify cumulative rewards<br>7. Test reward animations<br>8. Verify reward persistence |
| **Expected Results** | Rewards calculated based on performance<br>New stickers unlocked appropriately<br>Collection displays all earned rewards<br>Animations play smoothly<br>Rewards persist across sessions<br>No duplicate rewards<br>Reward history maintained |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-012
**Test Case Name:** Assessment Dashboard

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify assessment results display and AI prediction |
| **Pre-Conditions** | Pre-assessment completed |
| **Test Steps** | 1. Navigate to Assessment Dashboard<br>2. View results summary<br>3. Verify profile display<br>4. Check AI prediction if available<br>5. Verify scoring breakdown<br>6. Test retake assessment button<br>7. Verify data accuracy<br>8. Test landscape/portrait layouts |
| **Expected Results** | Results display without scrolling (landscape)<br>Profile generated from rubric scoring<br>AI prediction shown with confidence<br>Scoring breakdown accurate<br>Retake button functional<br>All data matches assessment<br>Layout adapts to orientation |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-013
**Test Case Name:** Offline-First Data Sync

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify data persistence and sync when online |
| **Pre-Conditions** | Authenticated user, Network available |
| **Test Steps** | 1. Use app with network on<br>2. Verify sync to Supabase<br>3. Turn off network<br>4. Create/modify data locally<br>5. Verify local storage<br>6. Turn network back on<br>7. Verify sync triggered<br>8. Check data consistency<br>9. Test conflict resolution |
| **Expected Results** | Data saves locally first (always)<br>Mark pending flag set for new data<br>Sync triggered when online<br>Guest mode: no sync attempted<br>Authenticated: sync to Supabase<br>Conflict resolution handles edge cases<br>No data loss during sync |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-014
**Test Case Name:** Local Database Operations

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify SQLite CRUD operations and migrations |
| **Pre-Conditions** | App installed |
| **Test Steps** | 1. Test create operations<br>2. Test read operations<br>3. Test update operations<br>4. Test delete operations<br>5. Verify database schema<br>6. Test migration scripts<br>7. Verify data integrity<br>8. Test error handling |
| **Expected Results** | All CRUD operations successful<br>Schema matches entity models<br>Migrations apply correctly<br>No data loss on upgrade<br>Foreign key constraints enforced<br>Error handling graceful<br>Performance acceptable |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Unit test environment  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-015
**Test Case Name:** AI Assessment Scoring

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify XGBoost model loading and prediction |
| **Pre-Conditions** | Assessment data available |
| **Test Steps** | 1. Load XGBoost model<br>2. Prepare assessment features<br>3. Run prediction<br>4. Verify confidence score<br>5. Test model error handling<br>6. Verify result interpretation<br>7. Test fallback to rubric<br>8. Validate prediction accuracy |
| **Expected Results** | Model loads successfully<br>Features extracted correctly<br>Prediction returns valid result<br>Confidence score in valid range<br>Graceful fallback on model error<br>Results integrated with dashboard<br>Performance within limits |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-016
**Test Case Name:** Rubric-Based Scoring

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify rubric scoring service calculations |
| **Pre-Conditions** | Assessment results available |
| **Test Steps** | 1. Provide assessment results<br>2. Apply rubric rules<br>3. Calculate weighted scores<br>4. Generate support profile<br>5. Test edge cases<br>6. Verify category mapping<br>7. Test threshold handling<br>8. Validate output format |
| **Expected Results** | Rules applied correctly<br>Weights calculated accurately<br>Profile categories assigned properly<br>Thresholds handled correctly<br>Edge cases produce valid results<br>Output matches expected format<br>Performance acceptable |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Unit test environment  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-017
**Test Case Name:** Audio Service Integration

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify background music and audio management |
| **Pre-Conditions** | App launched |
| **Test Steps** | 1. Launch app<br>2. Verify background music starts<br>3. Test music toggle<br>4. Navigate between screens<br>5. Verify music continuity<br>6. Test game audio overlay<br>7. Verify resource cleanup<br>8. Test audio focus handling |
| **Expected Results** | Music starts on app launch<br>Toggle controls work<br>Music continues across screens<br>Game audio plays without conflict<br>Resources properly released<br>Audio focus handled correctly<br>No audio leaks or crashes |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-018
**Test Case Name:** Voice Over System

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify composite voice over queue and playback |
| **Pre-Conditions** | Sensory settings with voice over enabled |
| **Test Steps** | 1. Enable voice over<br>2. Navigate to voiced screen<br>3. Listen to voice queue<br>4. Test interrupt and resume<br>5. Test composite voices<br>6. Verify queue management<br>7. Test voice cancellation<br>8. Check voice settings |
| **Expected Results** | Voices play in sequence<br>Queue managed correctly<br>Composite voices assembled properly<br>Interrupt/resume works<br>No overlapping voices<br>Settings applied correctly<br>Performance smooth |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-019
**Test Case Name:** OTP Verification

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify OTP delivery and validation |
| **Pre-Conditions** | User initiating registration/reset |
| **Test Steps** | 1. Request OTP<br>2. Verify delivery (SMS/Email)<br>3. Enter valid OTP<br>4. Submit verification<br>5. Test invalid OTP<br>6. Test expired OTP<br>7. Test resend functionality<br>8. Verify rate limiting |
| **Expected Results** | OTP delivered within time limit<br>Valid OTP accepted<br>Invalid OTP rejected with error<br>Expired OTP rejected<br>Resend works after delay<br>Rate limiting enforced<br>Session established on success |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-020
**Test Case Name:** Password Reset Flow

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify password reset end-to-end workflow |
| **Pre-Conditions** | Registered user with valid email |
| **Test Steps** | 1. Tap "Forgot Password"<br>2. Enter registered email<br>3. Request reset link<br>4. Check email delivery<br>5. Click reset link<br>6. Enter new password<br>7. Confirm new password<br>8. Submit reset<br>9. Login with new password |
| **Expected Results** | Reset email sent<br>Link valid for limited time<br>New password accepted<br>Confirmation password validated<br>Old password invalidated<br>New login succeeds<br>Secure token handling |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-021
**Test Case Name:** Home Screen Navigation

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify navigation and state restoration |
| **Pre-Conditions** | User logged in with child profile |
| **Test Steps** | 1. Navigate to Home screen<br>2. Tap each menu item<br>3. Verify destination<br>4. Test back navigation<br>5. Kill and restart app<br>6. Verify state restored<br>7. Test deep links<br>8. Verify logout flow |
| **Expected Results** | All menu items functional<br>Correct screens displayed<br>Back navigation works<br>State persists after restart<br>Deep links handled<br>Logout clears session<br>No navigation loops |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** September 2026  
**Tester:** Parent/Guardian Testers

---

### TEST CASE ID: TC-AU-022
**Test Case Name:** Parent Waiting Screen

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify parent approval flow for transitions |
| **Pre-Conditions** | Child attempting to navigate to restricted area |
| **Test Steps** | 1. Trigger parent gate<br>2. Verify waiting screen<br>3. Test parent approval<br>4. Test timeout handling<br>5. Test cancellation<br>6. Verify child lock<br>7. Test multiple attempts<br>8. Check audit logging |
| **Expected Results** | Waiting screen displays correctly<br>Parent approval unlocks<br>Timeout returns to previous<br>Cancellation handled<br>Child cannot bypass<br>Multiple attempts tracked<br>Audit trail maintained |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** September 2026  
**Tester:** Parent/Guardian Testers

---

### TEST CASE ID: TC-AU-023
**Test Case Name:** Game Summary Dialog

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify game results display and interactions |
| **Pre-Conditions** | Game just completed |
| **Test Steps** | 1. Complete a game<br>2. View summary dialog<br>3. Verify score display<br>4. Check performance feedback<br>5. Test continue button<br>6. Test share functionality<br>7. Verify animation smoothness<br>8. Check data accuracy |
| **Expected Results** | Dialog appears after game<br>Score displayed accurately<br>Feedback appropriate<br>Continue proceeds correctly<br>Share functional (if implemented)<br>Animations performant<br>Data matches gameplay |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** September 2026  
**Tester:** Parent/Guardian Testers

---

### TEST CASE ID: TC-AU-024
**Test Case Name:** Loading Screen

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify app initialization and resource loading |
| **Pre-Conditions** | App not running |
| **Test Steps** | 1. Launch app<br>2. Observe loading screen<br>3. Verify resource preloading<br>4. Check music initialization<br>5. Test timeout handling<br>6. Verify error recovery<br>7. Check loading indicators<br>8. Measure load time |
| **Expected Results** | Loading screen displays<br>Resources preloaded<br>Music starts automatically<br>No indefinite loading<br>Errors handled gracefully<br>Progress indicators shown<br>Load time acceptable |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS Emulator or Physical Device  
**Testing Schedule:** September 2026  
**Tester:** Parent/Guardian Testers

---

### TEST CASE ID: TC-AU-025
**Test Case Name:** Supabase Integration

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify backend API connectivity and operations |
| **Pre-Conditions** | Network available, Supabase configured |
| **Test Steps** | 1. Test connection<br>2. Verify authentication API<br>3. Test database queries<br>4. Test real-time subscriptions<br>5. Verify error handling<br>6. Test retry logic<br>7. Check rate limiting<br>8. Validate data format |
| **Expected Results** | Connection established<br>Auth API responds correctly<br>Queries return valid data<br>Real-time updates work<br>Errors handled gracefully<br>Retry logic functional<br>Rate limits respected<br>Data format correct |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Integration test environment  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

### TEST CASE ID: TC-AU-026
**Test Case Name:** Child Profile Policy

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify birth date validation and policy enforcement |
| **Pre-Conditions** | Profile creation screen |
| **Test Steps** | 1. Test minimum age boundary (3 years)<br>2. Test maximum age boundary (12 years)<br>3. Test exact boundary dates<br>4. Test invalid dates<br>5. Test future dates<br>6. Test very old dates<br>7. Verify error messages<br>8. Test policy updates |
| **Expected Results** | 3-year minimum enforced<br>12-year maximum enforced<br>Boundary dates handled correctly<br>Invalid dates rejected<br>Future dates rejected<br>Old dates rejected<br>Error messages clear<br>Policy changes applied |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Unit test + Device  
**Testing Schedule:** August 2026  
**Tester:** Ruel Mendio

---

### TEST CASE ID: TC-AU-027
**Test Case Name:** Cross-Platform Compatibility

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify app works across different devices and OS versions |
| **Pre-Conditions** | Multiple test devices |
| **Test Steps** | 1. Test on Android (various API levels)<br>2. Test on iOS (various versions)<br>3. Test different screen sizes<br>4. Test different orientations<br>5. Verify UI adaptation<br>6. Test hardware features<br>7. Check performance<br>8. Verify functionality |
| **Expected Results** | Android 5.0+ supported<br>iOS 12+ supported<br>UI adapts to screen size<br>Landscape mode works<br>Portrait mode works<br>Hardware features functional<br>Performance acceptable<br>All features accessible |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Multiple physical devices  
**Testing Schedule:** September 2026  
**Tester:** Parent/Guardian Testers

---

### TEST CASE ID: TC-AU-028
**Test Case Name:** Accessibility Features

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify accessibility compliance |
| **Pre-Conditions** | Accessibility settings enabled |
| **Test Steps** | 1. Test screen reader compatibility<br>2. Verify touch target sizes<br>3. Check color contrast<br>4. Test voice control<br>5. Verify haptic feedback<br>6. Test high contrast mode<br>7. Check font scaling<br>8. Verify focus indicators |
| **Expected Results** | Screen reader announces correctly<br>Touch targets 48dp+<br>Contrast ratios compliant<br>Voice control functional<br>Haptic feedback provided<br>High contrast supported<br>Fonts scale properly<br>Focus visible |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS with accessibility tools  
**Testing Schedule:** September 2026  
**Tester:** SPED/SNeD Teacher

---

### TEST CASE ID: TC-AU-029
**Test Case Name:** Data Privacy Compliance

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify data handling security and privacy |
| **Pre-Conditions** | User data in system |
| **Test Steps** | 1. Verify data encryption<br>2. Test secure storage<br>3. Check data minimization<br>4. Verify consent handling<br>5. Test data export<br>6. Test data deletion<br>7. Check audit trails<br>8. Verify compliance |
| **Expected Results** | Sensitive data encrypted<br>Secure storage used<br>Only necessary data collected<br>Consent properly obtained<br>Data export functional<br>Deletion completes fully<br>Audit logs maintained<br>GDPR/COPPA compliant |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Security testing environment  
**Testing Schedule:** September 2026  
**Tester:** Adviser / IT Evaluator

---

### TEST CASE ID: TC-AU-030
**Test Case Name:** Performance Under Load

| Field | Details |
|-------|---------|
| **Test Scenario** | Verify app performance with extended use |
| **Pre-Conditions** | App running |
| **Test Steps** | 1. Monitor memory usage<br>2. Track CPU utilization<br>3. Measure frame rates<br>4. Test extended gameplay<br>5. Monitor battery drain<br>6. Check for memory leaks<br>7. Test rapid interactions<br>8. Verify stability |
| **Expected Results** | Memory usage stable<br>CPU utilization acceptable<br>Frame rate 30fps+<br>No degradation over time<br>Battery drain reasonable<br>No memory leaks detected<br>Rapid interactions handled<br>App remains stable |
| **Actual Results** | *(To be filled during testing)* |
| **Status** | *(Pending/Passed/Failed)* |

**Test Environment:** Android/iOS with profiling tools  
**Testing Schedule:** August 2026  
**Tester:** Benedict Paul Samson

---

## Testing Summary

| Category | Count |
|----------|-------|
| **Functional Testing** | 18 |
| **Integration Testing** | 8 |
| **UAT (User Acceptance Testing)** | 20 |
| **Unit Testing** | 3 |
| **Performance Testing** | 1 |
| **Security Testing** | 1 |
| **Total Test Cases** | 30 |

---

## Testing Resources

| Role | Name/Group | Responsibility |
|------|------------|----------------|
| **Developer / Functional Tester** | Ruel Mendio | Functional testing, game testing, UI/UX validation, authentication flows |
| **Developer / Integration Tester** | Benedict Paul Samson | Integration testing, database operations, API testing, performance testing |
| **UAT Participants** | Parent or Guardian Testers | User acceptance testing, real-world usage scenarios, device compatibility |
| **Validator** | SPED/SNeD Teacher or Practitioner | Accessibility validation, activity appropriateness, assessment accuracy |
| **Technical Reviewer** | Adviser / IT Evaluator | Security testing, technical evaluation, system architecture review |

---

## Testing Phases (Based on WBS Phase 4)

| Phase | WBS Reference | Description | Timeline | Testing Resource | Budget |
|-------|---------------|-------------|----------|------------------|--------|
| **Phase 4.1** | 4.1 Functional and Integration Testing | Unit, Integration, and Functional Testing | August 2026 | Ruel Mendio, Benedict Paul Samson | Php 400.00 |
| **Phase 4.2** | 4.2 User Acceptance Testing | UAT with parents/guardians, cross-platform testing | September 2026 | Parent/Guardian Testers, SPED Teacher | Php 400.00 |
| **Phase 4.3** | 4.3 Validator Review and Revision | Security review, technical evaluation, revisions | September 2026 | Adviser / IT Evaluator | Php 400.00 |

**Phase 4 Duration:** August - September 2026  
**Phase 4 Total Budget:** Php 1,200.00

---

## Module Testing Alignment

| WBS Module | Test Cases | Primary Tester |
|------------|------------|----------------|
| 3.1 Account Access and Child Profile Module | TC-AU-001 to TC-AU-003, TC-AU-019 to TC-AU-020, TC-AU-026 | Ruel Mendio |
| 3.2 Settings, Sensory Preferences, and Screen-Time Module | TC-AU-005, TC-AU-018, TC-AU-028 | Ruel Mendio, SPED Teacher |
| 3.3 Gamified Assessment and Gameplay Indicator Module | TC-AU-004, TC-AU-006 to TC-AU-012 | Ruel Mendio |
| 3.4 AI Assessment and Recommendation Module | TC-AU-015 to TC-AU-016 | Benedict Paul Samson |
| 3.5 Learning Module and Post-Assessment Module | TC-AU-023, TC-AU-028 | Parent/Guardian Testers |
| 3.6 Dashboard, Offline Support, and Premium Gateway Module | TC-AU-013 to TC-AU-014, TC-AU-025, TC-AU-029 | Benedict Paul Samson, Adviser |

---

*Document created for Aumazing Capstone Project*  
*Format based on standard testing plan templates*
