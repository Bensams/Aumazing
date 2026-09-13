import 'dart:io';

import 'package:aumazing/core/services/local_db_service.dart';
import 'package:aumazing/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'v20/v21 migration keeps legacy rows and adds nullable music choices',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final previousPath = await getDatabasesPath();
      final directory = await Directory.systemTemp.createTemp(
        'aumazing_music_track_',
      );
      final databasePath = path.join(directory.path, 'aumazing_offline.db');
      await databaseFactory.setDatabasesPath(directory.path);

      final legacy = await openDatabase(
        databasePath,
        version: 19,
        onCreate:
            (db, _) => db.execute('''
        CREATE TABLE ${LocalTables.children} (
          id TEXT PRIMARY KEY,
          music_category TEXT NOT NULL DEFAULT 'soft_relaxing'
        )
      '''),
      );
      await legacy.insert(LocalTables.children, {
        'id': 'legacy-child',
        'music_category': 'filipino_calm',
      });
      await legacy.close();

      final service = LocalDbService();
      addTearDown(() async {
        await service.close();
        await databaseFactory.deleteDatabase(databasePath);
        await databaseFactory.setDatabasesPath(previousPath);
        await directory.delete();
      });

      final migrated = await service.database;
      final columns = await migrated.rawQuery(
        'PRAGMA table_info(${LocalTables.children})',
      );
      final trackColumn = columns.singleWhere(
        (c) => c['name'] == 'music_track',
      );
      expect(trackColumn['notnull'], 0);
      final tracksColumn = columns.singleWhere(
        (c) => c['name'] == 'music_tracks',
      );
      expect(tracksColumn['notnull'], 0);
      final row = (await migrated.query(LocalTables.children)).single;
      expect(row['music_category'], 'filipino_calm');
      expect(row['music_track'], isNull);
      expect(row['music_tracks'], isNull);

      const track = 'bgm/filipino_calm/bamboo_breeze.ogg';
      await migrated.update(
        LocalTables.children,
        {'music_track': track},
        where: 'id = ?',
        whereArgs: ['legacy-child'],
      );
      expect(
        (await migrated.query(LocalTables.children)).single['music_track'],
        track,
      );

      const mix =
          '["bgm/soft_relaxing/breathing_pad.ogg",'
          '"bgm/nature_ambient/slow_ocean.ogg",'
          '"bgm/filipino_calm/bamboo_breeze.ogg"]';
      await migrated.update(
        LocalTables.children,
        {'music_tracks': mix},
        where: 'id = ?',
        whereArgs: ['legacy-child'],
      );
      expect(
        (await migrated.query(LocalTables.children)).single['music_tracks'],
        mix,
      );
    },
  );
}
