import 'dart:convert';
import 'dart:io';

import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v22: the parent questionnaire is stored against the assessment run it was
/// answered after, so pre and post answers pair with that run's results.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v22 adds a nullable run id, keeps old rows, and round-trips', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final previousPath = await getDatabasesPath();
    final directory = await Directory.systemTemp.createTemp(
      'aumazing_questionnaire_',
    );
    final databasePath = path.join(directory.path, 'aumazing_offline.db');
    await databaseFactory.setDatabasesPath(directory.path);

    // The v21 shape of the table: no assessment_run_id.
    final legacy = await openDatabase(
      databasePath,
      version: 21,
      onCreate:
          (db, _) => db.execute('''
        CREATE TABLE ${LocalTables.caregiverQuestionnaires} (
          id TEXT PRIMARY KEY,
          child_id TEXT NOT NULL,
          questionnaire_type TEXT NOT NULL,
          responses TEXT NOT NULL,
          completed_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          sync_error TEXT,
          sync_attempts INTEGER NOT NULL DEFAULT 0,
          last_synced_at TEXT,
          deleted_at TEXT,
          updated_at TEXT NOT NULL,
          local_created_at TEXT NOT NULL,
          owner_id TEXT
        )
      '''),
    );
    await legacy.insert(LocalTables.caregiverQuestionnaires, {
      'id': 'old-q',
      'child_id': 'child-1',
      'questionnaire_type': 'pre',
      'responses': '{}',
      'completed_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
      'local_created_at': '2026-01-01T00:00:00.000',
    });
    await legacy.close();

    final service = LocalDbService();
    addTearDown(() async {
      await service.close();
      await databaseFactory.deleteDatabase(databasePath);
      await databaseFactory.setDatabasesPath(previousPath);
      await directory.delete(recursive: true);
    });

    final migrated = await service.database;
    final columns = await migrated.rawQuery(
      'PRAGMA table_info(${LocalTables.caregiverQuestionnaires})',
    );
    final runColumn = columns.singleWhere(
      (c) => c['name'] == 'assessment_run_id',
    );
    expect(runColumn['notnull'], 0);

    await service.insertCaregiverQuestionnaire(
      id: 'new-q',
      childId: 'child-1',
      assessmentRunId: 'run-1',
      questionnaireType: 'post',
      responses: {
        'template_id': 'aumazing_parent_checklist',
        'domain_scores': {'communication': 75.0},
      },
    );

    final rows = await service.getCaregiverQuestionnaires('child-1');
    expect(rows.map((r) => r['id']), containsAll(['old-q', 'new-q']));
    final fresh = rows.singleWhere((r) => r['id'] == 'new-q');
    expect(fresh['assessment_run_id'], 'run-1');
    expect(fresh['sync_status'], 'pending', reason: 'queued for upload');
    expect(
      (jsonDecode(fresh['responses'] as String) as Map)['domain_scores'],
      {'communication': 75.0},
    );
    final old = rows.singleWhere((r) => r['id'] == 'old-q');
    expect(old['assessment_run_id'], isNull);
  });
}
