import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web build: point sqflite at the WASM (`sqlite3.wasm`) factory.
///
/// We use the *no-web-worker* variant, which runs SQLite on the main thread.
/// The SharedWorker-based factory (`databaseFactoryFfiWeb`) requires the
/// `sqflite_sw.js` worker to instantiate, which fails in some embedded browser
/// engines. The no-worker path has no such dependency, still persists to the
/// browser (IndexedDB), and is more than enough for the web demo.
void initPlatformDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}
