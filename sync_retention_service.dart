import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'local_db.dart';
import 'export_service.dart';

class SyncAndRetentionService {
  static Future<bool> hasInternet() async {
    final res = await Connectivity().checkConnectivity();
    return !res.contains(ConnectivityResult.none);
  }

  static Future<String?> compressImage(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final r = await FlutterImageCompress.compressAndGetFile(sourcePath, target, quality: 60, minWidth: 1024, minHeight: 1024);
    return r?.path;
  }

  static Future<void> syncAll() async {
    if (!await hasInternet()) return;
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;
    final db = await LocalDatabase.instance.database;

    for (final s in await db.query('stations', where: "sync_status != 'synced'")) {
      try {
        await sb.from('stations').upsert({'id': s['id'], 'name': s['name'], 'normalized_name': s['normalized_name'], 'created_by': user.id}, onConflict: 'normalized_name');
        await db.update('stations', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [s['id']]);
      } catch (_) {}
    }
    try {
      for (final rs in await sb.from('stations').select()) {
        await db.insert('stations', {'id': rs['id'], 'name': rs['name'], 'normalized_name': rs['normalized_name'], 'sync_status': 'synced'}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (_) {}

    for (final t in await db.query('trips', where: "sync_status != 'synced'")) {
      try {
        await sb.from('trips').upsert({
          'id': t['id'], 'trip_date': t['trip_date'], 'driver_id': t['driver_id'], 'vehicle_number': t['vehicle_number'],
          'loading_station': t['loading_station'], 'unloading_station': t['unloading_station'], 'via_stations': t['via_stations'],
          'goods_name': t['goods_name'], 'quantity': t['quantity'], 'unit': t['unit'], 'bilty_number': t['bilty_number'],
          'kilometres': t['kilometres'], 'diesel_litres': t['diesel_litres'], 'notes': t['notes'], 'updated_at': DateTime.now().toIso8601String(),
        });
        await db.update('trips', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [t['id']]);
      } catch (_) {}
    }

    for (final h in await db.query('hisab_entries', where: "sync_status != 'synced'")) {
      try {
        await sb.from('hisab_entries').upsert({
          'id': h['id'], 'entry_date': h['entry_date'], 'driver_id': h['driver_id'], 'entry_type': h['entry_type'],
          'category': h['category'], 'amount': h['amount'], 'details': h['details'], 'updated_at': DateTime.now().toIso8601String(),
        });
        await db.update('hisab_entries', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [h['id']]);
      } catch (_) {}
    }

    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final duty = await sb.from('duty_assignments').select('*, vehicles(vehicle_number)').eq('driver_id', user.id).eq('duty_date', today).maybeSingle();
      if (duty != null && duty['vehicles'] != null) {
        await LocalDatabase.instance.setConfig('today_vehicle', duty['vehicles']['vehicle_number']);
      }
    } catch (_) {}
  }

  static Future<int> getTripsPendingRetentionReminderCount() async {
    final db = await LocalDatabase.instance.database;
    final cutoff30 = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
    return (await db.query('trips', where: 'trip_date <= ?', whereArgs: [cutoff30])).length;
  }

  static Future<void> enforce38DayRetentionPolicy() async {
    final db = await LocalDatabase.instance.database;
    final cutoff38 = DateTime.now().subtract(const Duration(days: 38)).toIso8601String().substring(0, 10);
    final expired = await db.query('trips', where: "trip_date <= ? AND sync_status = 'synced'", whereArgs: [cutoff38]);
    if (expired.isEmpty) return;
    await ExportService.createAutoRetentionBackup(expired);
    for (final t in expired) {
      await db.delete('trips', where: 'id = ?', whereArgs: [t['id']]);
    }
  }
}
