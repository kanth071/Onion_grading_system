import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../time_utils.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

/// Landing screen for the desktop-style shell (NavigationRail + Dashboard/
/// New Inspection/History/Analytics/Settings) - a summary of activity plus
/// quick access to the most recent inspections, rather than an empty page.
class DashboardScreen extends StatefulWidget {
  final VoidCallback onNewInspection;
  final VoidCallback onViewAllHistory;
  const DashboardScreen({super.key, required this.onNewInspection, required this.onViewAllHistory});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load dashboard: ${snapshot.error}',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            ),
          );
        }
        final list = (snapshot.data ?? []).cast<Map<String, dynamic>>();
        final total = list.length;
        final g1 = list.where((r) => r['grade'] == 'Grade 1').length;
        final urs = list.where((r) => r['grade'] == 'URS').length;
        final avgQuality = total == 0
            ? 0.0
            : list.map((r) => (r['grade_a_pct'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / total;
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final thisWeek = list.where((r) {
          final d = tryParseDate(r['created_at'] as String?);
          return d != null && d.isAfter(weekAgo);
        }).length;
        final recent = list.take(5).toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _WelcomeBanner(onNewInspection: widget.onNewInspection),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              final cards = [
                StatCard(label: 'Total Inspections', value: '$total', sublabel: '+$thisWeek this week'),
                StatCard(label: 'Grade 1 Batches', value: '$g1',
                    sublabel: total > 0 ? '${(100 * g1 / total).toStringAsFixed(0)}% of total' : null,
                    valueColor: AppColors.green),
                StatCard(label: 'Average Quality', value: '${avgQuality.toStringAsFixed(1)}%', sublabel: 'across all batches'),
                StatCard(label: 'URS Batches', value: '$urs',
                    sublabel: total > 0 ? '${(100 * urs / total).toStringAsFixed(0)}% of total' : null,
                    valueColor: AppColors.red),
              ];
              if (wide) {
                return Row(
                  children: cards
                      .map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c)))
                      .toList(),
                );
              }
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: cards,
              );
            }),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Inspections', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                TextButton(onPressed: widget.onViewAllHistory, child: const Text('View all →')),
              ],
            ),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('No inspections yet.', style: TextStyle(color: AppColors.muted))),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: recent.asMap().entries.map((entry) {
                    final r = entry.value;
                    final id = r['id'] as String;
                    final grade = r['grade'] as String? ?? 'URS';
                    final created = tryParseDate(r['created_at'] as String?);
                    return InkWell(
                      onTap: () => _openDetail(id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: entry.key < recent.length - 1
                              ? const Border(bottom: BorderSide(color: AppColors.border))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text('#${id.split('-').last}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            Expanded(
                              child: Text('${r['grade_a_pct']}%',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            ),
                            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: GradeChip(grade: grade))),
                            Text(created != null ? relativeTime(created) : '-',
                                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final VoidCallback onNewInspection;
  const _WelcomeBanner({required this.onNewInspection});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [AppColors.green, AppColors.greenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Opacity(
              opacity: .18,
              child: Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.eco, size: 60, color: AppColors.greenDark),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Smart. Consistent. Data-Driven Onion Grading.',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Upload or capture an onion batch image and receive an AI-powered quality\nassessment within seconds.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onNewInspection,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.greenDark),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Inspection'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
