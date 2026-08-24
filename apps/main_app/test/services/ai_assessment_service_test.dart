import 'dart:convert';

import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/services/ai_assessment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('raw-session AI request does not include child identity', () async {
    late Map<String, dynamic> request;
    final client = MockClient((requestMessage) async {
      request = jsonDecode(requestMessage.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({
        'predicted_profile': 'balanced_profile',
        'confidence': 0.8,
        'recommended_modules': <dynamic>[],
      }), 200);
    });
    final service = AiAssessmentService(baseUrl: 'https://ai.test', client: client);
    final session = GameplaySession(
      id: 'session-1',
      childId: 'child-secret',
      gameId: 'match_it',
      context: 'pre_assessment',
      score: 4,
      totalItems: 5,
      errorCount: 1,
      totalResponseTimeMs: 2000,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026, 1, 1, 0, 1),
    );

    await service.predictFromSessions(childId: 'child-secret', sessions: [session]);

    expect(request.containsKey('child_id'), isFalse);
    expect(request['sessions'], isA<List<dynamic>>());
    service.dispose();
  });
}
