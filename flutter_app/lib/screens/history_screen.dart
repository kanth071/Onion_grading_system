import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../time_utils.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

class HistoryScreen extends StatefulWidget {
  /// True when shown as a shell tab (inside RootShell). False when pushed as
  /// its own route — that needs its own Scaffold/AppBar with a back arrow.
  final bool embedded;
  const HistoryScreen({super.key, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

const _gradeFilters = ['All Grades', 'Grade 1', 'Grade 2', 'URS', 'No Detection'];

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<dynamic>> _future;
  final _searchCtrl = TextEditingController();
  String _gradeFilter = 'All Grades';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
        final list = (snapshot.data ?? []).cast<Map<String, dynamic>>();
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

        final counts = {'Grade 1': 0, 'Grade 2': 0, 'URS': 0};
        for (final r in list) {
          final g = r['grade'] as String?;
          if (counts.containsKey(g)) counts[g!] = counts[g]! + 1;
        }

        final q = _searchCtrl.text.trim().toLowerCase();
        final filtered = list.where((r) {
          final grade = r['grade'] as String? ?? 'URS';
          final gradeLabel = grade == 'NO_DETECTION' ? 'No Detection' : grade;
          if (_gradeFilter != 'All Grades' && gradeLabel != _gradeFilter) return false;
          if (q.isNotEmpty) {
            final id = (r['id'] as String? ?? '').toLowerCase();
            final label = (r['batch_label'] as String? ?? '').toLowerCase();
            if (!id.contains(q) && !label.contains(q)) return false;
          }
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final chips = [
                _StatChip(label: 'Total Batches', value: '${list.length}', color: AppColors.ink),
                _StatChip(label: 'Grade 1', value: '${counts["Grade 1"]}', color: AppColors.green),
                _StatChip(label: 'Grade 2', value: '${counts["Grade 2"]}', color: AppColors.orange),
                _StatChip(label: 'URS', value: '${counts["URS"]}', color: AppColors.red),
              ];
              return Wrap(spacing: 24, runSpacing: 10, children: chips);
            }),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search Batch ID…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _gradeFilter,
                  underline: const SizedBox.shrink(),
                  items: _gradeFilters.map((g) => DropdownMenuItem(value: g, child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(g, style: const TextStyle(fontSize: 13)),
                  ))).toList(),
                  onChanged: (v) => setState(() => _gradeFilter = v ?? 'All Grades'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Expanded(flex: 2, child: Text('BATCH ID', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3))),
                      Expanded(child: Text('DATE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3))),
                      Expanded(child: Text('QUALITY', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3))),
                      Expanded(flex: 2, child: Text('GRADE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3))),
                    ]),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No matching inspections.', style: TextStyle(color: AppColors.muted))),
                    )
                  else
                    ...filtered.asMap().entries.map((entry) {
                      final r = entry.value;
                      final id = r['id'] as String;
                      final grade = r['grade'] as String? ?? 'URS';
                      final created = tryParseDate(r['created_at'] as String?);
                      return InkWell(
                        onTap: () => _openDetail(id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            border: entry.key < filtered.length - 1
                                ? const Border(bottom: BorderSide(color: AppColors.border))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('#${id.split('-').last}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              Expanded(child: Text(created != null ? shortDate(created) : '-', style: const TextStyle(fontSize: 13, color: AppColors.muted))),
                              Expanded(child: Text('${r['grade_a_pct']}%', style: const TextStyle(fontSize: 13))),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: GradeChip(grade: grade),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection History')),
      body: body,
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
    ]);
  }
}
