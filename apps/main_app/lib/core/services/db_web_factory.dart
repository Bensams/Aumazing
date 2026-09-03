import 'db_web_factory_stub.dart'
    if (dart.library.html) 'db_web_factory_web.dart' as impl;

/// Installs the correct sqflite `databaseFactory` for the current platform.
///
/// On mobile/desktop this is a no-op — sqflite registers its own native factory
/// automatically. On the web there is no native factory, so this swaps in the
/// WASM-backed one from `sqflite_common_ffi_web`, which persists the database in
/// the browser (IndexedDB). Call once, early in `main()`, before any
/// [LocalDbService] access.
void initPlatformDatabaseFactory() => impl.initPlatformDatabaseFactory();
