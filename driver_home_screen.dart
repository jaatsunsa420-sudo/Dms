import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_config.dart';
import '../services/local_db.dart';
import '../services/sync_retention_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../main.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  int _tabIndex = 0;
  int _pendingSync = 0;
  int _retentionWarnCount = 0;
  String _assignedVehicle = 'Not Assigned';
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _hisab = [];
  bool _isHolidayToday = false;

  @override
  void initState() {
    super.initState();
    _loadLocalState();
    _triggerBackgroundSync();
  }

  Future<void> _triggerBackgroundSync() async {
    await SyncAndRetentionService.syncAll();
    await SyncAndRetentionService.enforce38DayRetentionPolicy();
    await _loadLocalState();
  }

  Future<void> _loadLocalState() async {
    final db = await LocalDatabase.instance.database;
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final trips = await db.query('trips', where: 'driver_id = ?', whereArgs: [userId], orderBy: 'trip_date DESC, created_at DESC');
    final hisab = await db.query('hisab_entries', where: 'driver_id = ?', whereArgs: [userId], orderBy: 'entry_date DESC, created_at DESC');
    final pending = await LocalDatabase.instance.getPendingSyncCount();
    final warn30 = await SyncAndRetentionService.getTripsPendingRetentionReminderCount();
    final cache = await db.query('master_cache', where: "key = 'today_vehicle'");
    final hol = await db.query('attendance_logs', where: "driver_id = ? AND log_date = ? AND status = 'Holiday'", whereArgs: [userId, today]);

    if (!mounted) return;
    setState(() {
      _trips = trips;
      _hisab = hisab;
      _pendingSync = pending;
      _retentionWarnCount = warn30;
      _assignedVehicle = cache.isNotEmpty ? cache.first['value'] as String : 'Any / Select';
      _isHolidayToday = hol.isNotEmpty;
    });
  }

  Future<void> _markTodayHoliday() async {
    final db = await LocalDatabase.instance.database;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.insert('attendance_logs', {
      'id': const Uuid().v4(), 'log_date': today, 'driver_id': userId, 'status': 'Holiday', 'reason': 'Marked by driver', 'sync_status': 'pending',
    });
    await NotificationService.cancelTodayReminder();
    await _loadLocalState();
    SyncAndRetentionService.syncAll();
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.t('Download / View Trip Records', 'ट्रिप रिकॉर्ड डाउनलोड / देखें'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(leading: const Icon(Icons.table_chart, color: Colors.green), title: const Text('Excel Format (.xlsx)'), onTap: () async { Navigator.pop(context); final f = await ExportService.generateTripsExcel(_trips); await ExportService.shareFile(f); }),
              ListTile(leading: const Icon(Icons.description, color: Colors.blue), title: const Text('Word Format (.docx)'), onTap: () async { Navigator.pop(context); final f = await ExportService.generateTripsDocx(_trips, 'Driver'); await ExportService.shareFile(f); }),
              ListTile(leading: const Icon(Icons.picture_as_pdf, color: Colors.red), title: const Text('PDF Document (.pdf)'), onTap: () async { Navigator.pop(context); final f = await ExportService.generateTripsPdf(_trips, 'Driver'); await ExportService.shareFile(f); }),
              ListTile(leading: const Icon(Icons.grid_on, color: Colors.orange), title: const Text('CSV File (.csv)'), onTap: () async { Navigator.pop(context); final f = await ExportService.generateTripsCsv(_trips); await ExportService.shareFile(f); }),
              ListTile(leading: const Icon(Icons.phone_android, color: Colors.indigo), title: const Text('Mobile Readable Table / मोबाइल टेबल'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => MobileTableScreen(trips: _trips))); }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final monthPrefix = today.substring(0, 7);
    final todayTrips = _trips.where((t) => t['trip_date'] == today).length;
    double todayInc = 0, todayExp = 0, monthInc = 0, monthExp = 0, advRec = 0;
    for (final h in _hisab) {
      final amt = (h['amount'] as num).toDouble();
      final dt = h['entry_date'] as String;
      final type = h['entry_type'] as String;
      if (type == 'Advance') advRec += amt;
      if (dt == today) { if (type == 'Income') todayInc += amt; if (type == 'Expense') todayExp += amt; }
      if (dt.startsWith(monthPrefix)) { if (type == 'Income') monthInc += amt; if (type == 'Expense') monthExp += amt; }
    }

    final pages = [
      RefreshIndicator(
        onRefresh: _triggerBackgroundSync,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_retentionWarnCount > 0)
              Card(
                color: Colors.amber.shade100,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                  title: Text(AppStrings.t('$_retentionWarnCount trips are 30+ days old! Download backup before day 38 auto-cleanup.', '$_retentionWarnCount ट्रिप 30 दिन से पुरानी हैं! 38 दिन पूरे होने से पहले डाउनलोड करें।')),
                  trailing: ElevatedButton(onPressed: _showExportSheet, child: const Text('Download')),
                ),
              ),
            Card(
              color: const Color(0xFF0F294A),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.t("Today's Assigned Vehicle", "आज की गाड़ी"), style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(_assignedVehicle, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sync Pending: $_pendingSync', style: TextStyle(color: _pendingSync == 0 ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                        if (!_isHolidayToday)
                          TextButton.icon(onPressed: _markTodayHoliday, icon: const Icon(Icons.beach_access, color: Colors.white), label: Text(AppStrings.t('Mark Holiday', 'छुट्टी दर्ज करें'), style: const TextStyle(color: Colors.white)))
                        else
                          const Chip(label: Text('Holiday Marked ✅')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.55, crossAxisSpacing: 10, mainAxisSpacing: 10,
              children: [
                _statBox(AppStrings.t("Today's Trips", "आज की ट्रिप"), '$todayTrips', Colors.blue),
                _statBox(AppStrings.t("Total History", "कुल ट्रिप"), '${_trips.length}', Colors.indigo),
                _statBox(AppStrings.t("Today's Hisab (Net)", "आज का हिसाब"), '₹${(todayInc - todayExp).toStringAsFixed(0)}', Colors.teal),
                _statBox(AppStrings.t("Monthly Net / Adv Bal", "मासिक / एडवांस बैलेंस"), '₹${(monthInc - monthExp).toStringAsFixed(0)} | Adv: ₹${(advRec - monthExp).toStringAsFixed(0)}', Colors.deepPurple),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D6CE0), foregroundColor: Colors.white),
                onPressed: () => setState(() => _tabIndex = 1),
                icon: const Icon(Icons.add_road, size: 26),
                label: Text(AppStrings.t('+ ADD NEW TRIP', '+ नई ट्रिप जोड़ें'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      NewTripForm(defaultVehicle: _assignedVehicle, onSaved: () async { await _loadLocalState(); setState(() => _tabIndex = 2); }),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${AppStrings.t("Trips", "ट्रिप्स")}: ${_trips.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(onPressed: _showExportSheet, icon: const Icon(Icons.download), label: Text(AppStrings.t('Export / Table', 'डाउनलोड / टेबल'))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _trips.length,
              itemBuilder: (_, i) {
                final t = _trips[i];
                final synced = t['sync_status'] == 'synced';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text('${t['loading_station']} ➔ ${t['unloading_station']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${t['trip_date']} | ${t['vehicle_number']} | ${t['goods_name']} (${t['quantity']} ${t['unit']})'),
                    trailing: Icon(synced ? Icons.cloud_done : Icons.cloud_upload, color: synced ? Colors.green : Colors.orange),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      HisabScreen(entries: _hisab, onSaved: _loadLocalState),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('🚚 Driver Manager'),
        backgroundColor: const Color(0xFF0F294A),
        foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: () => setState(() => AppStrings.isHindi = !AppStrings.isHindi), child: Text(AppStrings.isHindi ? 'EN' : 'हिंदी', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.sync), onPressed: _triggerBackgroundSync),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async { await Supabase.instance.client.auth.signOut(); if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard), label: AppStrings.t('Home', 'होम')),
          NavigationDestination(icon: const Icon(Icons.add_circle), label: AppStrings.t('New Trip', 'नई ट्रिप')),
          NavigationDestination(icon: const Icon(Icons.history), label: AppStrings.t('History', 'इतिहास')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet), label: AppStrings.t('Hisab', 'हिसाब')),
        ],
      ),
    );
  }

  Widget _statBox(String title, String val, Color color) {
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)), const SizedBox(height: 6), Text(val, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis)])));
  }
}

class NewTripForm extends StatefulWidget {
  final String defaultVehicle;
  final VoidCallback onSaved;
  const NewTripForm({super.key, required this.defaultVehicle, required this.onSaved});
  @override
  State<NewTripForm> createState() => _NewTripFormState();
}

class _NewTripFormState extends State<NewTripForm> {
  final _vehCtrl = TextEditingController(), _fromCtrl = TextEditingController(), _toCtrl = TextEditingController(), _viaCtrl = TextEditingController(), _goodsCtrl = TextEditingController(), _qtyCtrl = TextEditingController(), _biltyCtrl = TextEditingController(), _kmCtrl = TextEditingController(), _dieselCtrl = TextEditingController(), _notesCtrl = TextEditingController();
  String _unit = 'Ton';
  final String _date = DateTime.now().toIso8601String().substring(0, 10);
  String? _loadPhoto, _unloadPhoto, _biltyPhoto;

  @override
  void initState() {
    super.initState();
    if (widget.defaultVehicle != 'Not Assigned' && widget.defaultVehicle != 'Any / Select') _vehCtrl.text = widget.defaultVehicle;
  }

  Future<void> _pickPhoto(int type) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;
    final compressed = await SyncAndRetentionService.compressImage(picked.path);
    setState(() { if (type == 1) _loadPhoto = compressed; if (type == 2) _unloadPhoto = compressed; if (type == 3) _biltyPhoto = compressed; });
  }

  Future<void> _saveTrip() async {
    if (_vehCtrl.text.trim().isEmpty || _fromCtrl.text.trim().isEmpty || _toCtrl.text.trim().isEmpty || _goodsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle, Loading, Unloading & Goods are required')));
      return;
    }
    final db = await LocalDatabase.instance.database;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    const uuid = Uuid();
    await LocalDatabase.instance.saveStationIfNew(_fromCtrl.text, uuid.v4());
    await LocalDatabase.instance.saveStationIfNew(_toCtrl.text, uuid.v4());

    await db.insert('trips', {
      'id': uuid.v4(), 'trip_date': _date, 'driver_id': userId, 'vehicle_number': _vehCtrl.text.trim().toUpperCase(),
      'loading_station': _fromCtrl.text.trim(), 'unloading_station': _toCtrl.text.trim(), 'via_stations': _viaCtrl.text.trim(),
      'goods_name': _goodsCtrl.text.trim(), 'quantity': double.tryParse(_qtyCtrl.text) ?? 0, 'unit': _unit,
      'bilty_number': _biltyCtrl.text.trim(), 'kilometres': _kmCtrl.text.isEmpty ? null : double.tryParse(_kmCtrl.text),
      'diesel_litres': _dieselCtrl.text.isEmpty ? null : double.tryParse(_dieselCtrl.text),
      'loading_photo_local': _loadPhoto, 'unloading_photo_local': _unloadPhoto, 'bilty_photo_local': _biltyPhoto,
      'notes': _notesCtrl.text.trim(), 'sync_status': 'pending', 'created_at': DateTime.now().toIso8601String(),
    });
    await NotificationService.cancelTodayReminder();
    SyncAndRetentionService.syncAll();
    widget.onSaved();
  }

  Widget _stationAutocomplete(String label, TextEditingController controller) {
    return Autocomplete<String>(
      optionsBuilder: (val) async => await LocalDatabase.instance.searchStations(val.text),
      onSelected: (selection) => controller.text = selection,
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmitted) {
        textCtrl.addListener(() => controller.text = textCtrl.text);
        return TextField(controller: textCtrl, focusNode: focusNode, decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.location_on)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(controller: _vehCtrl, decoration: InputDecoration(labelText: AppStrings.t('Vehicle Number *', 'गाड़ी नंबर *'))),
        const SizedBox(height: 10),
        _stationAutocomplete(AppStrings.t('Loading Station *', 'लोडिंग स्टेशन *'), _fromCtrl),
        const SizedBox(height: 10),
        _stationAutocomplete(AppStrings.t('Unloading Station *', 'अनलोडिंग स्टेशन *'), _toCtrl),
        const SizedBox(height: 10),
        TextField(controller: _viaCtrl, decoration: InputDecoration(labelText: AppStrings.t('Via Stations', 'बीच के स्टेशन'))),
        const SizedBox(height: 10),
        TextField(controller: _goodsCtrl, decoration: InputDecoration(labelText: AppStrings.t('Goods Name *', 'माल का नाम *'))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: AppStrings.t('Quantity', 'मात्रा')))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(value: _unit, items: ['Ton', 'Kg', 'Pieces', 'Bag', 'Litre'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (v) => setState(() => _unit = v!), decoration: const InputDecoration(labelText: 'Unit'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _biltyCtrl, decoration: InputDecoration(labelText: AppStrings.t('Bilty Number', 'बिल्टी नंबर'))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _kmCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM (Optional)'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _dieselCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diesel L (Optional)'))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _pickPhoto(1), icon: Icon(_loadPhoto != null ? Icons.check_circle : Icons.camera_alt), label: const Text('Loading Photo')),
          OutlinedButton.icon(onPressed: () => _pickPhoto(2), icon: Icon(_unloadPhoto != null ? Icons.check_circle : Icons.camera_alt), label: const Text('Unloading Photo')),
          OutlinedButton.icon(onPressed: () => _pickPhoto(3), icon: Icon(_biltyPhoto != null ? Icons.check_circle : Icons.camera_alt), label: const Text('Bilty Photo')),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _notesCtrl, decoration: InputDecoration(labelText: AppStrings.t('Notes', 'नोट्स'))),
        const SizedBox(height: 18),
        SizedBox(height: 52, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white), onPressed: _saveTrip, child: Text(AppStrings.t('SAVE TRIP', 'ट्रिप सेव करें'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
      ],
    );
  }
}

class HisabScreen extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final VoidCallback onSaved;
  const HisabScreen({super.key, required this.entries, required this.onSaved});
  @override
  State<HisabScreen> createState() => _HisabScreenState();
}

class _HisabScreenState extends State<HisabScreen> {
  String _type = 'Expense', _category = 'Diesel';
  final _amtCtrl = TextEditingController(), _detCtrl = TextEditingController();
  List<String> get _categories => _type == 'Income' ? ['Trip Income', 'Other Income'] : _type == 'Advance' ? ['Office Advance', 'Advance Received'] : ['Diesel', 'Food', 'Toll', 'Parking', 'Repair', 'Other Expenses'];

  Future<void> _saveHisab() async {
    final amt = double.tryParse(_amtCtrl.text);
    if (amt == null || amt <= 0) return;
    final db = await LocalDatabase.instance.database;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await db.insert('hisab_entries', {
      'id': const Uuid().v4(), 'entry_date': DateTime.now().toIso8601String().substring(0, 10), 'driver_id': userId,
      'entry_type': _type, 'category': _category, 'amount': amt, 'details': _detCtrl.text.trim(), 'sync_status': 'pending', 'created_at': DateTime.now().toIso8601String(),
    });
    _amtCtrl.clear(); _detCtrl.clear();
    SyncAndRetentionService.syncAll();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        DropdownButtonFormField<String>(value: _type, items: ['Income', 'Advance', 'Expense'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() { _type = v!; _category = _categories.first; }), decoration: const InputDecoration(labelText: 'Entry Type')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: _category, items: _categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _category = v!), decoration: const InputDecoration(labelText: 'Category')),
        const SizedBox(height: 10),
        TextField(controller: _amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
        const SizedBox(height: 10),
        TextField(controller: _detCtrl, decoration: const InputDecoration(labelText: 'Details')),
        const SizedBox(height: 12),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F294A), foregroundColor: Colors.white), onPressed: _saveHisab, child: const Text('Save Hisab Entry')),
        const Divider(height: 28),
        ...widget.entries.map((h) => ListTile(
          leading: Icon(h['entry_type'] == 'Income' ? Icons.arrow_downward : h['entry_type'] == 'Advance' ? Icons.account_balance : Icons.arrow_upward, color: h['entry_type'] == 'Income' ? Colors.green : h['entry_type'] == 'Advance' ? Colors.orange : Colors.red),
          title: Text('${h['category']} - ₹${h['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${h['entry_date']} | ${h['details'] ?? ''}'),
        )),
      ],
    );
  }
}

class MobileTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> trips;
  const MobileTableScreen({super.key, required this.trips});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Records Table')),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
            columns: const [DataColumn(label: Text('Date')), DataColumn(label: Text('Vehicle')), DataColumn(label: Text('From')), DataColumn(label: Text('To')), DataColumn(label: Text('Goods')), DataColumn(label: Text('Qty')), DataColumn(label: Text('Bilty')), DataColumn(label: Text('KM')), DataColumn(label: Text('Diesel'))],
            rows: trips.map((t) => DataRow(cells: [DataCell(Text('${t['trip_date']}')), DataCell(Text('${t['vehicle_number']}')), DataCell(Text('${t['loading_station']}')), DataCell(Text('${t['unloading_station']}')), DataCell(Text('${t['goods_name']}')), DataCell(Text('${t['quantity']} ${t['unit']}')), DataCell(Text('${t['bilty_number'] ?? '-'}')), DataCell(Text('${t['kilometres'] ?? '-'}')), DataCell(Text('${t['diesel_litres'] ?? '-'}'))])).toList(),
          ),
        ),
      ),
    );
  }
}
