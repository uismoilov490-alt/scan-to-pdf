import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/pdf_service.dart';

class PreviewScreen extends StatefulWidget {
  final List<File> pages;

  const PreviewScreen({super.key, required this.pages});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _nameController;
  late final List<int> _quarterTurns; // 0=0°, 1=90°, 2=180°, 3=270°
  bool _generating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _quarterTurns = List.filled(widget.pages.length, 0);
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    _nameController = TextEditingController(text: 'Hujjat_$now');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _rotatePage(int index) {
    setState(() => _quarterTurns[index] = (_quarterTurns[index] + 1) % 4);
  }

  Future<void> _generatePdf() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'file_name_error'.tr());
      return;
    }

    setState(() {
      _generating = true;
      _errorMessage = null;
    });

    try {
      final file = await PdfService.generatePdf(
        imageFiles: widget.pages,
        fileName: name,
        quarterTurns: _quarterTurns,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'pdf_saved'.tr(namedArgs: {'name': file.path.split('/').last}),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _errorMessage = 'error_prefix'.tr(
            namedArgs: {'message': e.toString()},
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overlayFill = cs.scrim.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        title: Text(
          'pages_count'.tr(
            namedArgs: {'count': widget.pages.length.toString()},
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: widget.pages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: RotatedBox(
                            quarterTurns: _quarterTurns[index],
                            child: Image.file(
                              widget.pages[index],
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: overlayFill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1} / ${widget.pages.length}',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'rotate_$index',
                          onPressed: () => _rotatePage(index),
                          backgroundColor: overlayFill,
                          foregroundColor: cs.onPrimary,
                          elevation: 0,
                          child: const Icon(Icons.rotate_right),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            color: cs.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'file_name_label'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'file_name_hint'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    errorText: _errorMessage,
                    suffixText: '.pdf',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SafeArea(
                  top: false,
                  child: FilledButton.icon(
                    onPressed: _generating ? null : _generatePdf,
                    icon: _generating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(
                      _generating ? 'pdf_generating'.tr() : 'save_pdf'.tr(),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
