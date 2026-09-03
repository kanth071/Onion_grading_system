import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../grading_labels.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _downloading = false;

  static const _rows = [
    ['healthy', 'Healthy'],
    ['damaged', 'Damaged'],
    ['rotten', 'Rotten'],
    ['sprouted', 'Sprouted'],
    ['undersized', 'Undersized'],
  ];

  Future<void> _downloadReport() async {
    setState(() => _downloading = true);
    try {
      final id = widget.result['id'] as String;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${id}_report.pdf';
      await ApiClient.instance.downloadReport(id, path);
      await OpenFilex.open(path);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $err')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final total = (r['total_onions'] as num?)?.toDouble() ?? 0;
    final safeTotal = total <= 0 ? 1.0 : total;
    final grade = r['grade'] as String? ?? 'URS';
    final gradeAPct = (r['grade_a_pct'] as num?)?.toDouble() ?? 0;
    final avgConf = (r['avg_confidence'] as num?)?.toDouble() ?? 0;
    final lowConf = r['low_confidence'] == true;
    final calibrated = r['undersized_calibrated'] == true;
    final price = (r['estimated_price_per_quintal'] as num?)?.toDouble() ?? 0;
    final pricingNote = (r['pricing'] is Map) ? (r['pricing']['note'] as String? ?? '') : 'Demo/configurable pricing.';
    final images = (r['images_json'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Inspection Result'), actions: homeAppBarActions(context)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${r['id']}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                Text('${r['num_images']} image(s) analyzed · ${r['total_onions']} onions detected',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 14),
                const Text('Quality Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ..._rows.map((row) {
                  final key = row[0];
                  final count = (r[key] as num?)?.toInt() ?? 0;
                  final pct = (count / safeTotal) * 100;
                  return BreakdownRow(classKey: key, label: row[1], count: count, pct: pct);
                }),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                GradeBadge(
                  grade: grade,
                  displayText: gradeLabel(grade),
                  subtitle: 'Grade-A (healthy): ${gradeAPct.toStringAsFixed(1)}%',
                ),
                if (grade != 'Grade 1' && dominantDefect(r) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Primary factor: ${dominantDefect(r)!.label} (${dominantDefect(r)!.pct.toStringAsFixed(1)}%)',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 12),
                ConfidencePill(confidence: avgConf, low: lowConf),
                if (lowConf) const WarnBox(text: '⚠️ Low confidence — manual verification recommended.'),
                if (!calibrated)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('Undersized check not calibrated for this inspection.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12), textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: 'Estimated Price',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹ ${price.toStringAsFixed(0)} / quintal',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(pricingNote, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          if (images.isNotEmpty)
            SectionCard(
              title: 'Annotated Images',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 10, runSpacing: 6, children: const [
                    _LegendDot(classKey: 'healthy', label: 'Healthy'),
                    _LegendDot(classKey: 'damaged', label: 'Damaged'),
                    _LegendDot(classKey: 'rotten', label: 'Rotten'),
                    _LegendDot(classKey: 'sprouted', label: 'Sprouted'),
                    _LegendDot(classKey: 'undersized', label: 'Undersized'),
                  ]),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    children: images.map((img) {
                      final url = ApiClient.instance.absoluteImageUrl(img['annotated_url'] as String);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(url, fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(color: AppColors.border)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: _downloading ? null : _downloadReport,
            icon: _downloading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            label: const Text('Download PDF Report'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('New Inspection'),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String classKey;
  final String label;
  const _LegendDot({required this.classKey, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.forClass(classKey), shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}
