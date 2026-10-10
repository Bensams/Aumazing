# Automated quality verification

Verified on 2026-10-08 with Flutter 3.44.8 and Dart 3.12.2.

## Evidence levels

- **Unit/widget**: deterministic Flutter or Deno tests; not device/browser E2E.
- **Host integration**: `integration_test` journey running on `flutter-tester`; validates the flow but not a deployed browser or physical device.
- **Device/browser integration**: the same journey executed through `flutter drive` on the named target.
- **BLOCKED**: required runtime or local service was unavailable.
- **N/A**: deliberately excluded, usually to avoid shared or production writes.

## Implemented product inventory and evidence

| Surface | Automated evidence | Current result |
|---|---|---|
| Authentication and onboarding | Main-app auth, splash, launch-target, child-setup, sound-preference, and portal login widget tests; denied portal login host journey | PASS (unit/widget and host integration) |
| Child profiles | Policy, persistence, multi-child, allowance, switching, setup, management, and deletion tests | PASS (unit/widget) |
| Games: Match It, Copy Me, Do What I Say, My Turn Your Turn, Sari-Sari Sort, Trace It, Hintay, Ano'ng Susunod, Sabay Tayo, Kumusta, Ano'ng Nararamdaman, Tulong Kaibigan | Full `game_core` suite plus a real stepped distractor/correct-card drag through `GameWidget` | PASS (271 package tests; host integration). Physical-device E2E BLOCKED |
| Pre/post assessment | Round plans, telemetry, handoff, initialization, result navigation, completeness, comparison, and interruption/resume tests | PASS (unit/widget) |
| Parent intake | Reuse/update provenance, current-session reset, required answers, skipped form, and save failure behavior | PASS (unit/widget and host integration) |
| Home questionnaire | All 16 questions, four domain scores, optional skip, failed save, retry, and repeated-save protection | PASS (unit/widget and host integration) |
| Session observations/check-ins | Optional skip, per-game/session answers, provenance, and handoff behavior | PASS (unit/widget and host integration) |
| Learning paths | Path service, mastery, child-mode route continuity, map layout, and victory behavior | PASS (unit/widget) |
| Rewards/shop | Star rules, awards, shop layout, ownership geometry, costumes, and reward voice behavior | PASS (unit/widget) |
| History and reports | Parent history, activity reports, PDF/report sharing, comparison, and metric explanations | PASS (unit/widget) |
| Summaries | Assessment and overall-gameplay summaries, provider fallback, unavailable-provider fallback, and parent-context prompt rules | PASS (Flutter and Deno unit tests) |
| Settings | Appearance, music, screen-time status, child management, account binding/deletion, and Premium plan tests | PASS (unit/widget) |
| Subscriptions/payments | Entitlements, expiry, simulated checkout, web return, webhook outcomes, refund, replay, and ownership checks | PASS (unit/widget and 47 Deno payment tests). Live payment N/A |
| Offline/sync | Local database, offline progress, hydration conflicts, child sync, schema contracts, and questionnaire run migration | PASS (unit/widget). Live recovery NOT RUN |
| Administrator portal | Login, practitioner approval, questionnaire validation/activation, built-in templates, editing, versioning, preview, and save | PASS (36 widget tests; 4 host-integration journeys). Browser E2E BLOCKED (`dwds` connection timeout) |
| Practitioner portal | Application state, role restrictions, copy/edit/version/preview/save flows | PASS (widget and host integration). Browser E2E BLOCKED |

## Accessibility, responsive, visual, and performance evidence

| Check | Result | Evidence |
|---|---|---|
| Mobile assessment responsive matrix | PASS | 360×800, 800×360, 800×1280 at 1.3× text, and 1280×800 at 2× text |
| Mobile intake accessibility | PASS | Android tap targets, labeled tap targets, and text contrast guidelines |
| Portal login responsive/keyboard matrix | PASS | 360×800, 768×1024 at 1.3× text, and 1440×900 at 2× text; keyboard submit exercised |
| Portal login accessibility | PASS | Android tap targets, labeled tap targets, and text contrast guidelines |
| Portal questionnaire editor responsiveness | PASS | Actions remain present and the final preview/save section is reachable at four widths |
| Custom-drawn shape contrast | PASS | Pixel tests verify a 3:1 contour and visible halo for star, triangle, diamond, heart, and circle |
| Picture/glyph emphasis | PASS | Pixel shadow and scalable glyph-shadow tests |
| Portal Chrome E2E | BLOCKED | `flutter drive -d chrome` failed with `AppConnectionException` from `dwds` (Dart Web Debug Service could not connect within 39 s). This is a web-toolchain infrastructure issue, not a test-code failure. The 4/4 host-integration results remain valid |
| Game/portal screenshots | BLOCKED unless run with ChromeDriver or a supported device | Screenshot calls remain enabled by default in device/browser runs and can be disabled only with `E2E_SCREENSHOTS=false` for host-harness diagnosis |
| Profile frame timing | BLOCKED | Requires a physical Android device and `--profile`; the test enforces both profile mode and explicit frame/startup budgets |

## Reproducible commands and observed results

Run from each listed directory.

```bash
# apps/main_app
flutter test
# PASS: 1,119 tests

flutter test test/quality/accessibility_responsive_test.dart
# PASS: 2 tests

flutter test integration_test/assessment_questionnaire_journey_test.dart \
  -d flutter-tester \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=E2E_SCREENSHOTS=false
# PASS: 3 host-integration tests

flutter test integration_test/gameplay_input_test.dart \
  -d flutter-tester \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=E2E_SCREENSHOTS=false
# PASS: 1 real-pointer host-integration test
```

```bash
# apps/admin_portal
flutter test
# PASS: 36 tests

flutter test integration_test/questionnaire_browser_test.dart \
  -d flutter-tester \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=E2E_SCREENSHOTS=false
# PASS: 4 host-integration tests
```

```bash
# packages/game_core
flutter test
# PASS: 271 tests

# packages/questionnaire_core
flutter test
# PASS: 10 tests

# packages/shared_ui
flutter test
# PASS: 184 tests

# packages/shared_audio
flutter test
# PASS: 137 tests

# apps/game_lab
flutter test
# PASS: 3 tests

# packages/shared_haptic
# N/A: no test directory exists
```

Focused analysis of the changed integration and quality files passed without errors. Broader analysis retained pre-existing non-error diagnostics: five informational diagnostics in `main_app`, one `anonKey` deprecation in `admin_portal`, and 26 warning/information diagnostics in `game_core`.

```bash
# supabase
deno test functions/tests
# PASS: 62 tests

./tests/run_rls_tests.sh
# BLOCKED: Docker Desktop engine unavailable
```

### Browser execution

A matching ChromeDriver must be listening on port 4444 before Flutter Web integration runs:

```bash
npx --yes chromedriver@154.0.1 --port=4444

# apps/admin_portal
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/questionnaire_browser_test.dart \
  -d chrome \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=E2E_SCREENSHOTS=true
# BLOCKED on 2026-10-08: dwds AppConnectionException after 39 s.
# The Dart Web Debug Service could not connect to the Chrome instance.
# Re-run when a stable ChromeDriver + Chrome pairing is available.
```

### Physical Android execution

```bash
# apps/main_app
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/assessment_questionnaire_journey_test.dart \
  -d <android-device-id> \
  --dart-define=E2E_TEST_MODE=true

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/gameplay_input_test.dart \
  -d <android-device-id> \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=E2E_SCREENSHOTS=true

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/performance_test.dart \
  -d <physical-android-device-id> \
  --profile \
  --dart-define=E2E_TEST_MODE=true
```

For an ordinary project-managed device launch, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Projects\aumazing\scripts\wifi-run.ps1" -Run -DevTools -NoPause
```

## Limits and safety boundaries

- No Android emulator or physical Android device was connected, so Android E2E, OS-dialog automation, screenshot capture, interruption by real process death, and profile frame timing remain BLOCKED.
- Host integration results are not presented as browser/device E2E.
- The RLS suite is isolated in a throwaway PostgreSQL container, but Docker Desktop was not running.
- Live Supabase and payment-provider integration is N/A for this run: deterministic fakes and pure edge-function tests were used, and no production or shared questionnaire data was changed.
- Integration-only seams live under `integration_test/` and require `E2E_TEST_MODE=true`; no test control was added to production runtime code.
- No deployment, push, remote mutation, or production data write was performed.
