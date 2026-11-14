import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;
  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fleet_driver_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    return await openDatabase(join(dbPath, filePath), version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE trips (
      id TEXT PRIMARY KEY, trip_date TEXT NOT NULL, driver_id TEXT NOT NULL, vehicle_number TEXT NOT NULL,
      loading_station TEXT NOT NULL, unloading_station TEXT NOT NULL, via_stations TEXT, goods_name TEXT NOT NULL,
      quantity REAL NOT NULL, unit TEXT NOT NULL, loading_time TEXT, unloading_time TEXT, bilty_number TEXT,
      kilometres REAL, diesel_litres REAL, loading_photo_local TEXT, unloading_photo_local TEXT, bilty_photo_local TEXT,
      loading_photo_url TEXT, unloading_photo_url TEXT, bilty_photo_url TEXT, notes TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE hisab_entries (
      id TEXT PRIMARY KEY, entry_date TEXT NOT NULL, driver_id TEXT NOT NULL, vehicle_number TEXT,
      entry_type TEXT NOT NULL, category TEXT NOT NULL, amount REAL NOT NULL, details TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE stations (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT UNIQUE NOT NULL, sync_status TEXT NOT NULL DEFAULT 'pending'
    )''');
    await db.execute('''CREATE TABLE attendance_logs (
      id TEXT PRIMARY KEY, log_date TEXT NOT NULL, driver_id TEXT NOT NULL, status TEXT NOT NULL,
      reason TEXT, sync_status TEXT NOT NULL DEFAULT 'pending', UNIQUE(log_date, driver_id)
    )''');
    await db.execute('''CREATE TABLE master_cache (key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
  }

  Future<void> saveStationIfNew(String rawName, String id) async {
    final clean = rawName.trim();
    if (clean.isEmpty) return;
    final norm = clean.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final db = await database;
    await db.insert('stations', {'id': id, 'name': clean, 'normalized_name': norm, 'sync_status': 'pending'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> searchStations(String query) async {
    final db = await database;
    final q = query.trim().toLowerCase();
    final res = q.isEmpty
        ? await db.query('stations', orderBy: 'name ASC', limit: 30)
        : await db.query('stations', where: 'normalized_name LIKE ?', whereArgs: ['%$q%'], orderBy: 'name ASC', limit: 15);
    return res.map((e) => e['name'] as String).toList();
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final t = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM trips WHERE sync_status != 'synced'")) ?? 0;
    final h = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM hisab_entries WHERE sync_status != 'synced'")) ?? 0;
    final s = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM stations WHERE sync_status != 'synced'")) ?? 0;
    return t + h + s;
  }

  Future<void> setConfig(String k, String v) async {
    final db = await database;
    await db.insert('master_cache', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfig(String k) async {
    final db = await database;
    final r = await db.query('master_cache', where: 'key = ?', whereArgs: [k]);
    return r.isNotEmpty ? r.first['value'] as String : null;
  }
}
