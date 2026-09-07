import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../app_nav.dart';
import '../grading_labels.dart';
import '../theme.dart';
import '../web_utils.dart';
import '../widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _downloading = false;

  Future<void> _downloadReport() async {
    final id = widget.result['id'] as String;
    if (kIsWeb) {
      // No filesystem, no OpenFilex on web - just open the PDF the same way
      // the existing web frontend already does.
      openUrlInNewTab(ApiClient.instance.reportUrl(id));
      return;
    }
    setState(() => _downloading = true);
    try {
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
    final grade = r['grade'] as String? ?? 'URS';
    final noDetection = grade == 'NO_DETECTION';
    final images = (r['images_json'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Dashboard',
          onPressed: () {
            // Land back on the Dashboard specifically (not whichever tab
            // this inspection was reached from) so the just-finished result
            // is immediately visible there, per explicit request.
            AppNav.goToTab(0);
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        title: const Text('Inspection Results'),
        actions: homeAppBarActions(context),
      ),
      body: noDetection ? _NoDetectionBody(result: r) : _buildSplitBody(context, r, images),
    );
  }

  Widget _buildSplitBody(BuildContext context, Map<String, dynamic> r, List images) {
    final imagePanel = _ImagePanel(images: images);
    final reportPanel = _ReportPanel(result: r, downloading: _downloading, onDownload: _downloadReport);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 760;
      if (wide) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: SingleChildScrollView(child: imagePanel)),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: SingleChildScrollView(child: reportPanel)),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            imagePanel,
            const SizedBox(height: 16),
            reportPanel,
          ],
        ),
      );
    });
  }
}

class _NoDetectionBody extends StatelessWidget {
  final Map<String, dynamic> result;
  const _NoDetectionBody({required this.result});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          child: Column(
            children: [
              const GradeBadge(
                grade: 'URS',
                displayText: '⚠ No Onions Detected',
                subtitle: 'The model found nothing to grade in this photo',
              ),
              const SizedBox(height: 10),
              const Text(
                'Retake the photo closer, with better lighting, so the batch fills the frame — then try again.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('New Inspection'),
        ),
      ],
    );
  }
}

class _ImagePanel extends StatelessWidget {
  final List images;
  const _ImagePanel({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < images.length; i++) ...[
          // A fixed max height (instead of an unconstrained Image inside a
          // plain Column) is what actually stops a tall/wide photo from
          // overflowing past the screen - "contain" alone only controls how
          // the image fits *within* whatever box it's given, not how big
          // that box gets to be.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                ApiClient.instance.absoluteImageUrl(images[i]['annotated_url'] as String),
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Container(
                  height: 200,
                  color: AppColors.border,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Fig. ${i + 1} — Batch image with AI detection overlay',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 14, runSpacing: 6, children: const [
          _LegendDot(classKey: 'healthy', label: 'Healthy'),
          _LegendDot(classKey: 'damaged', label: 'Damaged'),
          _LegendDot(classKey: 'rotten', label: 'Rotten'),
          _LegendDot(classKey: 'sprouted', label: 'Sprouted'),
        ]),
      ],
    );
  }
}

class _ReportPanel extends StatelessWidget {
  final Map<String, dynamic> result;
  final bool downloading;
  final VoidCallback onDownload;
  const _ReportPanel({required this.result, required this.downloading, required this.onDownload});

  static const _rows = [
    ['healthy', 'Healthy', false],
    ['damaged', 'Damaged', true],
    ['rotten', 'Rotten', true],
    ['sprouted', 'Sprouted', true],
  ];

  @override
  Widget build(BuildContext context) {
    final r = result;
    final total = (r['total_onions'] as num?)?.toDouble() ?? 0;
    final safeTotal = total <= 0 ? 1.0 : total;
    final grade = r['grade'] as String? ?? 'URS';
    final gradeAPct = (r['grade_a_pct'] as num?)?.toDouble() ?? 0;
    final avgConf = (r['avg_confidence'] as num?)?.toDouble() ?? 0;
    final lowConf = r['low_confidence'] == true;
    final majority = majorityClass(r);
    final defect = grade != 'Grade 1' ? dominantDefect(r) : null;
    final price = (r['estimated_price_per_quintal'] as num?)?.toDouble() ?? 0;
    final pricingNote = (r['pricing'] is Map) ? (r['pricing']['note'] as String? ?? '') : 'Demo/configurable pricing.';
    final gradeColor = AppColors.forGrade(grade);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('AI INSPECTION REPORT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.green, letterSpacing: .4)),
              Text('#${(r['id'] as String? ?? '').split('-').last}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OVERALL QUALITY SCORE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3)),
                    const SizedBox(height: 4),
                    Text('${gradeAPct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: gradeColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                child: Text(gradeLabel(grade).split(' — ')[0],
                    style: TextStyle(color: gradeColor, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SimpleProgressBar(pct: gradeAPct, color: gradeColor, height: 9),
          if (majority != null) ...[
            const SizedBox(height: 8),
            Text('Majority class: ${majority.label} (${majority.pct.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
          if (defect != null) ...[
            const SizedBox(height: 4),
            Text('Primary factor: ${defect.label} (${defect.pct.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          ConfidencePill(confidence: avgConf, low: lowConf),
          if (lowConf) const WarnBox(text: '⚠️ Low confidence — manual verification recommended.'),

          const SizedBox(height: 22),
          const Text('Quality Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ..._rows.map((row) {
            final key = row[0] as String;
            final label = row[1] as String;
            final isDefect = row[2] as bool;
            final count = (r[key] as num?)?.toInt() ?? 0;
            final pct = 100 * count / safeTotal;
            return _BreakdownBarRow(classKey: key, label: label, warn: isDefect, count: count, pct: pct);
          }),

          const SizedBox(height: 22),
          const Text('Estimated Market Value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('₹ ${price.toStringAsFixed(0)} / quintal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(pricingNote, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: downloading ? null : onDownload,
              icon: downloading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.ios_share, size: 18),
              label: const Text('Export Report'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per class: icon + dot + label on the left, count/pct on the
/// right, a full-width colored bar below - mirrors the web app's Quality
/// Breakdown exactly (frontend/app.js renderResults), row by row, instead of
/// a single combined segmented bar.
class _BreakdownBarRow extends StatelessWidget {
  final String classKey;
  final String label;
  final bool warn;
  final int count;
  final double pct;
  const _BreakdownBarRow({
    required this.classKey,
    required this.label,
    required this.warn,
    required this.count,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forClass(classKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(warn ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    size: 15, color: warn ? AppColors.orange : AppColors.green),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$count', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ],
          ),
          const SizedBox(height: 6),
          SimpleProgressBar(pct: pct, color: color, height: 6),
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
