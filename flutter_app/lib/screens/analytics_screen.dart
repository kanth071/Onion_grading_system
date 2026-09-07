import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../time_utils.dart';
import '../widgets/common.dart';

/// All charts here are computed client-side from the same /api/inspections
/// history the Dashboard and History screens already use - no new backend
/// endpoints needed for a first pass at trends/aggregates.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final data = await ApiClient.instance.getJson('/api/inspections?limit=200');
    return data as List<dynamic>;
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
              child: Text('Could not load analytics: ${snapshot.error}',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            ),
          );
        }
        final list = (snapshot.data ?? []).cast<Map<String, dynamic>>();
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No inspections yet - analytics will appear once you have some history.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            ),
          );
        }

        final total = list.length;
        final g1 = list.where((r) => r['grade'] == 'Grade 1').length;
        final g2 = list.where((r) => r['grade'] == 'Grade 2').length;
        final urs = list.where((r) => r['grade'] == 'URS').length;

        final totalOnions = list.fold<int>(0, (a, r) => a + ((r['total_onions'] as num?)?.toInt() ?? 0));
        final avgQuality = total == 0
            ? 0.0
            : list.map((r) => (r['grade_a_pct'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / total;

        final defectTotals = {'damaged': 0, 'rotten': 0, 'sprouted': 0};
        for (final r in list) {
          for (final k in defectTotals.keys) {
            defectTotals[k] = defectTotals[k]! + ((r[k] as num?)?.toInt() ?? 0);
          }
        }
        final defectTotal = defectTotals.values.fold(0, (a, b) => a + b);

        // Quality trend across the most recent inspections (not grouped by
        // calendar day) - a fresh deployment's history often spans a single
        // day for a long time, which would leave a day-bucketed trend empty
        // indefinitely. Plotting per-inspection is meaningful from the very
        // second real inspection onward.
        final withDates = list
            .map((r) => (r: r, d: tryParseDate(r['created_at'] as String?)))
            .where((e) => e.d != null)
            .toList()
          ..sort((a, b) => b.d!.compareTo(a.d!));
        final recentChrono = withDates.take(8).toList().reversed.toList();
        final trendPoints = recentChrono.map((e) => (e.r['grade_a_pct'] as num?)?.toDouble() ?? 0.0).toList();
        final trendLabels = recentChrono
            .map((e) => '${e.d!.hour.toString().padLeft(2, '0')}:${e.d!.minute.toString().padLeft(2, '0')}')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              final cards = [
                StatCard(label: 'Total Batches', value: '$total'),
                StatCard(label: 'Onions Inspected', value: '$totalOnions'),
                StatCard(label: 'Avg Quality', value: '${avgQuality.toStringAsFixed(1)}%'),
                StatCard(label: 'Grade 1 Rate', value: total > 0 ? '${(100 * g1 / total).toStringAsFixed(0)}%' : '0%', valueColor: AppColors.green),
              ];
              if (wide) {
                return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c))).toList());
              }
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: cards,
              );
            }),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 800;
              final distCard = _Card(
                title: 'Quality Distribution',
                subtitle: 'Share of all graded batches',
                child: Row(
                  children: [
                    DonutChart(
                      size: 130,
                      segments: [
                        DonutSegment(g1.toDouble(), AppColors.green),
                        DonutSegment(g2.toDouble(), AppColors.orange),
                        DonutSegment(urs.toDouble(), AppColors.red),
                      ],
                      centerLabel: '$total',
                      centerSubLabel: 'batches',
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendRow(label: 'Grade 1', count: g1, total: total, color: AppColors.green),
                          const SizedBox(height: 10),
                          _LegendRow(label: 'Grade 2', count: g2, total: total, color: AppColors.orange),
                          const SizedBox(height: 10),
                          _LegendRow(label: 'URS', count: urs, total: total, color: AppColors.red),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final trendCard = _Card(
                title: 'Inspection Trend vs. Grading Bands',
                subtitle: 'Quality score, last ${trendPoints.length} inspection(s)',
                child: SizedBox(
                  height: 190,
                  child: trendPoints.length < 2
                      ? const Center(child: Text('Need at least 2 inspections to show a trend.', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                      : CustomPaint(
                          size: Size.infinite,
                          painter: _TrendPainter(points: trendPoints, labels: trendLabels),
                        ),
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: distCard),
                    const SizedBox(width: 16),
                    Expanded(child: trendCard),
                  ],
                );
              }
              return Column(children: [distCard, const SizedBox(height: 16), trendCard]);
            }),
            const SizedBox(height: 16),
            _Card(
              title: 'Common Defects',
              subtitle: 'Share of all defective onions found, all history',
              child: defectTotal == 0
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No defects recorded yet.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    )
                  : Row(
                      children: [
                        DonutChart(
                          size: 110,
                          segments: [
                            DonutSegment(defectTotals['damaged']!.toDouble(), AppColors.orange),
                            DonutSegment(defectTotals['rotten']!.toDouble(), AppColors.red),
                            DonutSegment(defectTotals['sprouted']!.toDouble(), AppColors.purple),
                          ],
                          centerLabel: '$defectTotal',
                          centerSubLabel: 'defects',
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LegendRow(label: 'Damaged', count: defectTotals['damaged']!, total: defectTotal, color: AppColors.orange),
                              const SizedBox(height: 10),
                              _LegendRow(label: 'Rotten', count: defectTotals['rotten']!, total: defectTotal, color: AppColors.red),
                              const SizedBox(height: 10),
                              _LegendRow(label: 'Sprouted', count: defectTotals['sprouted']!, total: defectTotal, color: AppColors.purple),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Card({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;
  const _LegendRow({required this.label, required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? 100 * count / total : 0.0;
    return Row(
      children: [
        Container(width: 11, height: 11, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        Text('$count', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        SizedBox(width: 38, child: Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: AppColors.muted), textAlign: TextAlign.right)),
      ],
    );
  }
}

class DonutSegment {
  final double value;
  final Color color;
  DonutSegment(this.value, this.color);
}

/// A real pie/donut chart (not just stacked bars) - used for both grade
/// distribution and defect-type share, so "the graph" is an actual chart a
/// viewer can read a proportion off at a glance.
class DonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final double size;
  final String centerLabel;
  final String centerSubLabel;
  const DonutChart({super.key, required this.segments, required this.size, required this.centerLabel, required this.centerSubLabel});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _DonutPainter(segments)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerLabel, style: TextStyle(fontSize: size * 0.16, fontWeight: FontWeight.w800)),
              Text(centerSubLabel, style: TextStyle(fontSize: size * 0.08, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const strokeWidth = 16.0;
    final bg = Paint()
      ..color = const Color(0xFFEEECE3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect.deflate(strokeWidth / 2), 0, 2 * math.pi, false, bg);

    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = 2 * math.pi * (seg.value / total);
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(strokeWidth / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.segments != segments;
}

/// Trend line plus shaded Grade 1 / Grade 2 / URS bands - so a point's
/// position tells you not just "quality went up or down" but which grading
/// band it actually falls in, which is the thing that matters here.
class _TrendPainter extends CustomPainter {
  final List<double> points; // 0..100
  final List<String> labels;
  _TrendPainter({required this.points, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 22.0;
    const topPad = 6.0;
    final chartHeight = size.height - bottomPad - topPad;
    final stepX = points.length > 1 ? size.width / (points.length - 1) : 0.0;

    double yFor(double pct) => topPad + chartHeight * (1 - (pct.clamp(0, 100) / 100));

    // Grading bands: URS (0-60, red tint), Grade 2 (60-80, orange tint),
    // Grade 1 (80-100, green tint).
    void band(double from, double to, Color color) {
      canvas.drawRect(
        Rect.fromLTRB(0, yFor(to), size.width, yFor(from)),
        Paint()..color = color.withValues(alpha: 0.08),
      );
    }

    band(0, 60, AppColors.red);
    band(60, 80, AppColors.orange);
    band(80, 100, AppColors.green);

    final dashPaint = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (final threshold in [60.0, 80.0]) {
      final y = yFor(threshold);
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dashPaint);
        x += 8;
      }
    }
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    labelPainter.text = const TextSpan(text: 'Grade 1 ≥ 80%', style: TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w600));
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(size.width - labelPainter.width - 2, yFor(80) - 12));
    labelPainter.text = const TextSpan(text: 'Grade 2 ≥ 60%', style: TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w600));
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(size.width - labelPainter.width - 2, yFor(60) - 12));

    final linePath = Path()..moveTo(0, yFor(points.first));
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(stepX * i, yFor(points[i]));
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.greenDark
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < points.length; i++) {
      final x = stepX * i;
      final y = yFor(points[i]);
      final dotColor = points[i] >= 80 ? AppColors.green : (points[i] >= 60 ? AppColors.orange : AppColors.red);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()
        ..color = dotColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = dotColor);

      if (i < labels.length) {
        textPainter.text = TextSpan(text: labels[i], style: const TextStyle(fontSize: 10, color: AppColors.muted));
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - bottomPad + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.labels != labels;
}
