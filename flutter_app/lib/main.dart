import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';
import 'screens/upload_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.instance.load();
  runApp(const OnionGradingApp());
}

class OnionGradingApp extends StatelessWidget {
  const OnionGradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onion Quality Grading',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;

  Future<void> _editServerUrl() async {
    final ctrl = TextEditingController(text: ApiClient.instance.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend server URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'http://<PC-LAN-IP>:8000'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await ApiClient.instance.setBaseUrl(result.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server URL updated')));
        setState(() {}); // refresh dependent screens (History/Settings) via key change below
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧅 Onion Quality AI'),
        actions: [
          IconButton(icon: const Icon(Icons.settings_ethernet), tooltip: 'Server settings', onPressed: _editServerUrl),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        // KeyedSubtree with a fresh key forces History/Settings to reload after the server URL changes.
        children: [
          const UploadScreen(embedded: true),
          KeyedSubtree(
              key: ValueKey('history-${ApiClient.instance.baseUrl}'),
              child: const HistoryScreen(embedded: true)),
          KeyedSubtree(
              key: ValueKey('settings-${ApiClient.instance.baseUrl}'),
              child: const SettingsScreen(embedded: true)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        // App opens directly onto the camera (index 0) - no dashboard/menu in between.
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: 'Inspect'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'History'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Grading'),
        ],
      ),
    );
  }
}
