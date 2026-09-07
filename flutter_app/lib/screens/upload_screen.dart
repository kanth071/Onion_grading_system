import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'processing_screen.dart';

/// New Inspection screen — a capture card (camera or gallery) followed by a
/// short "how it works" strip so the flow is self-explanatory. No upfront
/// single-vs-batch choice: whatever ends up in the list gets analyzed
/// together when Analyze is tapped — 1 photo behaves like "single", 2+
/// behaves like "batch".
class UploadScreen extends StatefulWidget {
  /// See HistoryScreen.embedded — same tab-vs-pushed-route split. When
  /// embedded (a shell tab), there's no back arrow needed.
  final bool embedded;
  const UploadScreen({super.key, this.embedded = false});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<XFile> _files = [];
  final _batchLabelCtrl = TextEditingController();
  final _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (shot == null) return;
    setState(() => _files.add(shot));
  }

  Future<void> _pickFromGallery() async {
    final shots = await _picker.pickMultiImage(imageQuality: 90);
    if (shots.isEmpty) return;
    setState(() => _files.addAll(shots));
  }

  void _analyze() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          files: List.of(_files),
          mode: _files.length > 1 ? 'batch' : 'single',
          batchLabel: _batchLabelCtrl.text.trim().isEmpty ? null : _batchLabelCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CaptureCard(onCamera: _takePhoto, onGallery: _pickFromGallery),
          const SizedBox(height: 16),
          const _ProcessStrip(),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Batch ID / label (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _batchLabelCtrl, decoration: const InputDecoration(hintText: 'e.g. ON-2026-001')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_files.length, (i) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            // dart:io File works for the camera/gallery preview on
                            // native platforms, but Image.file asserts on Flutter
                            // Web - there, the picked file's path is already a
                            // usable blob: URL, so Image.network loads it fine.
                            child: kIsWeb
                                ? Image.network(_files[i].path, width: 84, height: 84, fit: BoxFit.cover)
                                : Image.file(File(_files[i].path), width: 84, height: 84, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _files.removeAt(i)),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _analyze,
                      child: Text(_files.length > 1 ? 'Analyze (${_files.length} photos)' : 'Analyze'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('New Inspection'), actions: homeAppBarActions(context)),
      body: body,
    );
  }
}

class _CaptureCard extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _CaptureCard({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.4),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt_outlined, color: AppColors.green, size: 26),
          ),
          const SizedBox(height: 16),
          const Text('Capture Onion Batch for Analysis',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Take a clear, well-lit photo of the complete batch, spread in\na single layer, for the most accurate grading.',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Open Camera'),
              ),
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Upload Image'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const WarnBox(
            text: '📸 Use a real photo of the actual batch — the AI is trained on real inspection '
                "photos, not glossy product/catalog photography, and won't read those reliably.",
          ),
        ],
      ),
    );
  }
}

class _ProcessStrip extends StatelessWidget {
  const _ProcessStrip();

  static const _steps = [
    (icon: Icons.camera_alt_outlined, title: 'Capture Image', sub: 'Photo of the full batch'),
    (icon: Icons.add_circle_outline, title: 'AI Detects Onions', sub: 'Every onion located & isolated'),
    (icon: Icons.bar_chart_outlined, title: 'Quality Analysis', sub: 'Defects classified'),
    (icon: Icons.emoji_events_outlined, title: 'Final Grade Generated', sub: 'Standardized grade & report'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Inspection Process', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 4,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            children: List.generate(_steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                return const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Icon(Icons.arrow_forward, size: 16, color: AppColors.muted),
                );
              }
              final s = _steps[i ~/ 2];
              return SizedBox(
                width: 120,
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(s.icon, color: AppColors.green, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(s.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text(s.sub, style: const TextStyle(fontSize: 10, color: AppColors.muted), textAlign: TextAlign.center),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
