import 'package:flutter/material.dart';
import '../theme.dart';

/// AppBar action that jumps straight back to the Home tab, regardless of
/// how many screens deep the user is (unlike the automatic back arrow,
/// which only goes up one level).
List<Widget> homeAppBarActions(BuildContext context) {
  return [
    IconButton(
      icon: const Icon(Icons.home_outlined),
      tooltip: 'Back to Home',
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
    ),
  ];
}

class BigActionButton extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool primary;
  final VoidCallback onTap;

  const BigActionButton({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: primary ? AppColors.green : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: primary ? null : Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: primary ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                if (subtitle == null)
                  Text(title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primary ? Colors.white : AppColors.ink,
                      ))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const SectionCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class GradeBadge extends StatelessWidget {
  final String grade;
  final String displayText;
  final String subtitle;
  const GradeBadge({super.key, required this.grade, required this.displayText, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forGrade(grade);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.15)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Text(displayText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: .3)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}

class BreakdownRow extends StatelessWidget {
  final String classKey;
  final String label;
  final int count;
  final double pct;
  const BreakdownRow({super.key, required this.classKey, required this.label, required this.count, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: AppColors.forClass(classKey), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
          ]),
          Row(children: [
            Text('$count', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ],
      ),
    );
  }
}

class ConfidencePill extends StatelessWidget {
  final double confidence; // 0..1
  final bool low;
  const ConfidencePill({super.key, required this.confidence, required this.low});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    final bg = low ? const Color(0xFFFDEAEA) : const Color(0xFFE4F6E9);
    final fg = low ? const Color(0xFFB31414) : const Color(0xFF1C8F3D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text('AI Confidence $pct%', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class WarnBox extends StatelessWidget {
  final String text;
  const WarnBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E0),
        border: Border.all(color: const Color(0xFFF0D98C)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF7A5C00), fontSize: 13)),
    );
  }
}

/// Small metric tile used on the Dashboard and History screens - a label,
/// a big value, and an optional muted sublabel (e.g. "+12 this week").
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final Color? valueColor;
  const StatCard({super.key, required this.label, required this.value, this.sublabel, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .3)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.ink)),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(sublabel!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

/// A single flat progress bar - used for "Overall Quality Score" and similar
/// single-value measures. For a segmented multi-class bar see [SegmentedBar].
class SimpleProgressBar extends StatelessWidget {
  final double pct; // 0..100
  final Color color;
  final double height;
  const SimpleProgressBar({super.key, required this.pct, required this.color, this.height = 10});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LayoutBuilder(builder: (context, constraints) {
        return Stack(children: [
          Container(height: height, color: const Color(0xFFEEECE3)),
          Container(height: height, width: constraints.maxWidth * (pct.clamp(0, 100) / 100), color: color),
        ]);
      }),
    );
  }
}

/// A single bar split into colored segments by percentage - used for the
/// "Quality Distribution" breakdown across healthy/damaged/rotten/sprouted.
class SegmentedBar extends StatelessWidget {
  final List<MapEntry<double, Color>> segments; // (pct 0..100, color)
  final double height;
  const SegmentedBar({super.key, required this.segments, this.height = 10});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: const Color(0xFFEEECE3),
        child: Row(
          children: segments.where((s) => s.key > 0).map((s) {
            return Expanded(flex: (s.key * 10).round().clamp(1, 1000), child: Container(color: s.value));
          }).toList(),
        ),
      ),
    );
  }
}

class GradeChip extends StatelessWidget {
  final String grade;
  const GradeChip({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.forGrade(grade), borderRadius: BorderRadius.circular(999)),
      child: Text(grade, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
