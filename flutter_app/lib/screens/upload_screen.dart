import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'processing_screen.dart';

/// The app's camera-first home screen. Opens directly onto this — no
/// dashboard/menu, and no upfront single-vs-batch choice. Tap "Take Photo"
/// as many times as needed; whatever ends up in the list gets analyzed
/// together as one inspection when Analyze is tapped — 1 photo behaves
/// like "single", 2+ behaves like "batch", with no mode to pick in advance.
class UploadScreen extends StatefulWidget {
  /// See HistoryScreen.embedded — same tab-vs-pushed-route split. When
  /// embedded (the Home tab), there's no back arrow needed.
  final bool embedded;
  const UploadScreen({super.key, this.embedded = false});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<File> _files = [];
  final _batchLabelCtrl = TextEditingController();
  final _pxPerCmCtrl = TextEditingController();
  final _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (shot == null) return;
    setState(() => _files.add(File(shot.path)));
  }

  Future<void> _pickFromGallery() async {
    final shots = await _picker.pickMultiImage(imageQuality: 90);
    if (shots.isEmpty) return;
    setState(() => _files.addAll(shots.map((x) => File(x.path))));
  }

  void _analyze() {
    final pxPerCm = double.tryParse(_pxPerCmCtrl.text.trim());
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          files: List.of(_files),
          mode: _files.length > 1 ? 'batch' : 'single',
          batchLabel: _batchLabelCtrl.text.trim().isEmpty ? null : _batchLabelCtrl.text.trim(),
          pxPerCm: pxPerCm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CameraButton(onTap: _takePhoto),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Choose from Gallery'),
            ),
          ),
          const SizedBox(height: 14),
          const WarnBox(
            text: '📸 Use a real photo of the actual batch (crate, tray, or table) — the AI is '
                "trained on real inspection photos, not glossy product/catalog photography, "
                "and won't read those reliably.",
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 14),
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
                            child: Image.file(_files[i], width: 84, height: 84, fit: BoxFit.cover),
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
          const SizedBox(height: 14),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Size calibration (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              children: [
                TextField(
                  controller: _pxPerCmCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Pixels per cm — leave blank to skip undersized detection'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Place a known reference object in-frame and enter its pixel width ÷ real width (cm) '
                  'to enable the "undersized" size check.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspect'), actions: homeAppBarActions(context)),
      body: body,
    );
  }
}

class _CameraButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.green,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [AppColors.green, Color.lerp(AppColors.green, Colors.black, 0.12)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt, color: Colors.white, size: 48),
              SizedBox(height: 6),
              Text('Take Photo', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
