import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final List<XFile> files;
  final String mode;
  final String? batchLabel;

  const ProcessingScreen({
    super.key,
    required this.files,
    required this.mode,
    this.batchLabel,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  static const _steps = [
    'Uploading photos',
    'Detecting onions',
    'Checking defects',
    'Calculating quality & grade',
  ];
  int _doneSteps = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (_doneSteps < _steps.length - 1) {
        setState(() => _doneSteps++);
      }
    });
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await ApiClient.instance.uploadInspection(
        files: widget.files,
        mode: widget.mode,
        batchLabel: widget.batchLabel,
      );
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _doneSteps = _steps.length);
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultsScreen(result: result)));
    } catch (err) {
      _timer?.cancel();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $err')),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyzing…'), actions: homeAppBarActions(context)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.green),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _doneSteps / _steps.length,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFEEEEEE),
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_steps.length, (i) {
                    final done = i < _doneSteps;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 16, color: done ? AppColors.green : AppColors.muted),
                          const SizedBox(width: 8),
                          Text(_steps[i],
                              style: TextStyle(
                                  fontSize: 13, color: done ? AppColors.ink : AppColors.muted)),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
