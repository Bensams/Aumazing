import 'package:admin_portal/pages/beta_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements BetaReportClient {
  _FakeClient({this.children = const [], this.report});

  final List<Map<String, dynamic>> children;
  final Map<String, dynamic>? report;
  int reportLoads = 0;

  @override
  Future<dynamic> loadChildren() async => children;

  @override
  Future<dynamic> loadThresholds() async => null;

  @override
  Future<dynamic> loadReport(String childId) async {
    reportLoads += 1;
    return report;
  }

  @override
  Future<void> submitReview({
    required String childId,
    required String area,
    required bool agrees,
    String? comment,
    String? reviewerId,
  }) async {}
}

const _childRow = {
  'child_id': 'child-1',
  'display_name': 'Test Child',
  'birth_date': '2022-04-20',
  'ai_training_opt_in': true,
  'consent_version': 1,
  'consented_at': '2026-08-01T00:00:00Z',
  'session_count': 4,
  'result_count': 2,
  'review_count': 0,
};

Map<String, dynamic> _reportWith(List<Map<String, dynamic>> comparisons) => {
      'child': {'id': 'child-1', 'display_name': 'Test Child'},
      'sessions': const [],
      'results': const [],
      'recommendations': const [],
      'comparisons': comparisons,
      'reviews': const [],
    };

const _comparison = {
  'id': 'comp-1',
  'compared_at': '2026-08-29T10:00:00Z',
  'overall_progress_status': 'improved',
  'comparison_summary_json': {
    'prompt_dependency_delta': '-0.15',
    'areas_improved': 3,
  },
  'baseline': {
    'assessment_date': '2026-08-01',
    'communication_level': '0',
    'social_level': 'emerging',
    'play_level': '1',
    'attention_level': 'needs_support',
  },
  'comparison': {
    'assessment_date': '2026-08-20',
    'communication_level': '2',
    'social_level': 'strength',
    'play_level': '2',
    'attention_level': 'emerging',
  },
};

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeClient client,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BetaPage(client: client))),
  );
  await tester.pumpAndSettle(); // children list loads
  await tester.tap(find.textContaining('Test Child'));
  await tester.pumpAndSettle(); // report loads and renders
}

void main() {
  testWidgets('renders the pre/post comparison with per-area deltas', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      client: _FakeClient(
        children: [_childRow],
        report: _reportWith([_comparison]),
      ),
    );

    expect(find.text('Pre vs Post Comparison'), findsOneWidget);
    expect(find.text('Improved'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);

    // Every area shows a baseline -> comparison transition.
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(4));

    // Level formatting normalizes slugs, ints, and display names.
    expect(find.text('Needs Support'), findsWidgets);
    expect(find.text('Strength'), findsWidgets);

    // The pipeline-owned summary is surfaced as readable rows.
    expect(find.text('Prompt dependency delta'), findsOneWidget);
    expect(find.text('-0.15'), findsOneWidget);
    expect(find.text('Areas improved'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    expect(find.textContaining('Compared'), findsOneWidget);
  });

  testWidgets('explains when no comparison has synced yet', (tester) async {
    await _pumpPage(
      tester,
      client: _FakeClient(
        children: [_childRow],
        report: _reportWith(const []),
      ),
    );

    expect(find.text('Pre vs Post Comparison'), findsOneWidget);
    expect(find.textContaining('No pre/post comparison synced yet'),
        findsOneWidget);
  });

  testWidgets('tolerates pre-AUM-330 reports without a comparisons key', (
    tester,
  ) async {
    final report = _reportWith(const [])..remove('comparisons');
    await _pumpPage(
      tester,
      client: _FakeClient(children: [_childRow], report: report),
    );

    expect(find.text('Pre vs Post Comparison'), findsOneWidget);
    expect(find.textContaining('No pre/post comparison synced yet'),
        findsOneWidget);
  });
}
