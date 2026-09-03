import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  /// See HistoryScreen.embedded — same tab-vs-pushed-route split.
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _cfg;
  String? _error;
  bool _saving = false;

  final _grade1 = TextEditingController();
  final _grade2 = TextEditingController();
  final _lowConf = TextEditingController();
  final _undersizedCm = TextEditingController();
  final _basePrice = TextEditingController();
  final _adjG1 = TextEditingController();
  final _adjG2 = TextEditingController();
  final _adjUrs = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cfg = await ApiClient.instance.getJson('/api/settings') as Map<String, dynamic>;
      setState(() {
        _cfg = cfg;
        _grade1.text = '${cfg['grade1_min_pct']}';
        _grade2.text = '${cfg['grade2_min_pct']}';
        _lowConf.text = '${cfg['low_confidence_threshold']}';
        _undersizedCm.text = '${cfg['undersized_diameter_cm']}';
        _basePrice.text = '${cfg['base_price_per_quintal']}';
        final adj = cfg['grade_price_adjustment_pct'] as Map<String, dynamic>;
        _adjG1.text = '${adj['Grade 1']}';
        _adjG2.text = '${adj['Grade 2']}';
        _adjUrs.text = '${adj['URS']}';
      });
    } catch (err) {
      setState(() => _error = '$err');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.putJson('/api/settings', {
        'grade1_min_pct': double.tryParse(_grade1.text) ?? 80.0,
        'grade2_min_pct': double.tryParse(_grade2.text) ?? 60.0,
        'low_confidence_threshold': double.tryParse(_lowConf.text) ?? 0.65,
        'undersized_diameter_cm': double.tryParse(_undersizedCm.text) ?? 4.0,
        'base_price_per_quintal': double.tryParse(_basePrice.text) ?? 2500.0,
        'grade_price_adjustment_pct': {
          'Grade 1': double.tryParse(_adjG1.text) ?? 10.0,
          'Grade 2': double.tryParse(_adjG2.text) ?? -5.0,
          'URS': double.tryParse(_adjUrs.text) ?? -20.0,
        },
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _cfg == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load settings: $_error\nIs the backend running at ${ApiClient.instance.baseUrl}?',
                          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Prototype thresholds — configurable, not official procurement standards.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'What the grades mean',
                  child: Column(
                    children: const [
                      _GradeMeaningRow(emoji: '🥇', name: 'Grade 1', meaning: 'High-quality onions'),
                      _GradeMeaningRow(emoji: '🥈', name: 'Grade 2', meaning: 'Acceptable, lower quality'),
                      _GradeMeaningRow(emoji: '❌', name: 'URS', meaning: 'Unfit for Sale — below minimum quality'),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Grading Engine',
                  child: Column(
                    children: [
                      _numField('Grade 1: Grade-A % ≥', _grade1),
                      _numField('Grade 2: Grade-A % ≥', _grade2),
                      const Text('Below Grade 2\'s threshold → URS / Below Standard.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 10),
                      _numField('Low-confidence threshold (flags manual review)', _lowConf),
                      _numField('Undersized diameter threshold (cm)', _undersizedCm),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Pricing Engine',
                  child: Column(
                    children: [
                      _numField('Base market price (₹ / quintal)', _basePrice),
                      Row(children: [
                        Expanded(child: _numField('Grade 1 adj (%)', _adjG1)),
                        const SizedBox(width: 8),
                        Expanded(child: _numField('Grade 2 adj (%)', _adjG2)),
                        const SizedBox(width: 8),
                        Expanded(child: _numField('URS adj (%)', _adjUrs)),
                      ]),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Settings'),
                ),
              ],
            );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Grading & Pricing Rules'), actions: homeAppBarActions(context)),
      body: body,
    );
  }
}

class _GradeMeaningRow extends StatelessWidget {
  final String emoji;
  final String name;
  final String meaning;
  const _GradeMeaningRow({required this.emoji, required this.name, required this.meaning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$emoji ', style: const TextStyle(fontSize: 14)),
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(child: Text(meaning, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
        ],
      ),
    );
  }
}
