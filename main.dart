import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/local_db.dart';
import 'services/sync_retention_service.dart';
import 'services/notification_service.dart';
import 'screens/driver_home_screen.dart';

bool supabaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final savedUrl = await LocalDatabase.instance.getConfig('sb_url');
  final savedKey = await LocalDatabase.instance.getConfig('sb_key');
  if (savedUrl != null && savedUrl.isNotEmpty && savedKey != null && savedKey.isNotEmpty) {
    await Supabase.initialize(url: savedUrl, anonKey: savedKey);
    supabaseInitialized = true;
  }
  runApp(const FleetDriverApp());
}

class FleetDriverApp extends StatelessWidget {
  const FleetDriverApp({super.key});
  @override
  Widget build(BuildContext context) {
    final loggedIn = supabaseInitialized && Supabase.instance.client.auth.currentSession != null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F294A)),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white),
      ),
      home: loggedIn ? const DriverHomeScreen() : const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSavedCreds();
  }

  Future<void> _loadSavedCreds() async {
    _urlCtrl.text = await LocalDatabase.instance.getConfig('sb_url') ?? '';
    _keyCtrl.text = await LocalDatabase.instance.getConfig('sb_key') ?? '';
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final url = _urlCtrl.text.trim();
      final key = _keyCtrl.text.trim();
      if (url.isEmpty || key.isEmpty) throw Exception('Enter Supabase URL and Key');
      await LocalDatabase.instance.setConfig('sb_url', url);
      await LocalDatabase.instance.setConfig('sb_key', key);
      if (!supabaseInitialized) {
        await Supabase.initialize(url: url, anonKey: key);
        supabaseInitialized = true;
      }
      await Supabase.instance.client.auth.signInWithPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text);
      await SyncAndRetentionService.syncAll();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriverHomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_shipping, size: 52, color: Color(0xFF0F294A)),
                  const SizedBox(height: 8),
                  const Text('Driver Manager Login', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'Supabase Project URL')),
                  const SizedBox(height: 10),
                  TextField(controller: _keyCtrl, decoration: const InputDecoration(labelText: 'Supabase Anon Key')),
                  const SizedBox(height: 10),
                  TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Driver Email')),
                  const SizedBox(height: 10),
                  TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 10), Text(_error, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F294A), foregroundColor: Colors.white),
                      onPressed: _loading ? null : _login,
                      child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('LOGIN / लॉगिन करें', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
