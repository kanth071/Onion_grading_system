import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

class HistoryScreen extends StatefulWidget {
  /// True when shown as a bottom-nav tab (inside RootShell's own Scaffold/AppBar).
  /// False when pushed as its own route (from the Dashboard button) — that
  /// needs its own Scaffold/AppBar with a Home shortcut and a back arrow.
  final bool embedded;
  const HistoryScreen({super.key, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final data = await ApiClient.instance.getJson('/api/inspections?limit=100');
    return data as List<dynamic>;
  }

  Future<void> _openDetail(String id) async {
    try {
      final detail = await ApiClient.instance.getJson('/api/inspections/$id') as Map<String, dynamic>;
      detail['pricing'] = {
        'estimated_price_per_quintal': detail['estimated_price_per_quintal'],
        'note': 'Demo/configurable pricing.',
      };
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ResultsScreen(result: detail)));
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load inspection: $err')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load history: ${snapshot.error}\nIs the backend running at ${ApiClient.instance.baseUrl}?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            );
          }
          final list = snapshot.data ?? [];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📭', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 10),
                    Text('No inspections yet.', style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = list[i] as Map<String, dynamic>;
              final id = r['id'] as String;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => _openDetail(id),
                  title: Text(id.replaceFirst('ON-', ''), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(r['batch_label'] ?? '-', style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${r['grade_a_pct']}%', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(width: 8),
                      GradeChip(grade: r['grade'] as String? ?? 'URS'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection History'), actions: homeAppBarActions(context)),
      body: body,
    );
  }
}
