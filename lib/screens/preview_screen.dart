import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ai_service.dart';
import '../services/document_cleaner.dart';
import '../services/api/api_client.dart';
import '../services/pdf_service.dart';

class PreviewScreen extends StatefulWidget {
  final List<File> pages;

  /// Skaner kontrast filtri; ML Kit skaneri rasmni o'zi tozalagan bo'lsa — false
  final bool enhance;

  /// Sahifalarni skaner sifatiga keltirish (soya/dog' tozalash) avtomatik yoqiladi
  final bool autoClean;

  const PreviewScreen({
    super.key,
    required this.pages,
    this.enhance = true,
    this.autoClean = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _nameController;
  late final List<int> _quarterTurns; // 0=0°, 1=90°, 2=180°, 3=270°
  bool _generating = false;
  String? _errorMessage;
  bool _naming = false;
  bool _aiNamed = false;
  bool _userEditedName = false;
  // null — asl holicha; aks holda tanlangan tozalash rejimi
  CleanMode? _clean;
  final Map<int, Uint8List> _cleaned = {};
  final Set<int> _cleaning = {};

  @override
  void initState() {
    super.initState();
    _quarterTurns = List.filled(widget.pages.length, 0);
    if (widget.autoClean) _clean = CleanMode.color;
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    _nameController = TextEditingController(text: 'Hujjat_$now');
    // context.locale initState ichida ishlatilmaydi — birinchi kadrdan keyin
    WidgetsBinding.instance.addPostFrameCallback((_) => _suggestName());
  }

  /// AI birinchi sahifaga qarab nom taklif qiladi. Foydalanuvchi o'zi nom
  /// yozishni boshlagan bo'lsa yoki xato bo'lsa — jim o'tkazib yuboramiz.
  Future<void> _suggestName() async {
    if (!ApiClient.isSignedIn || widget.pages.isEmpty) return;
    setState(() => _naming = true);
    try {
      final lang = context.locale.languageCode;
      final title = await AiService.suggestName(
        await widget.pages.first.readAsBytes(),
        lang: lang,
      );
      if (!mounted || _userEditedName || title.isEmpty) return;
      _nameController.text = title;
      setState(() => _aiNamed = true);
    } catch (_) {
      // Nom berish ixtiyoriy funksiya
    } finally {
      if (mounted) setState(() => _naming = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _rotatePage(int index) {
    setState(() => _quarterTurns[index] = (_quarterTurns[index] + 1) % 4);
  }

  /// Sahifaning tozalangan ko'rinishini fon rejimida tayyorlaydi (kesishsiz —
  /// skaner varaqni allaqachon kesgan).
  Future<Uint8List?> _cleanPage(int index) async {
    final mode = _clean;
    if (mode == null) return null;
    if (_cleaned.containsKey(index)) return _cleaned[index];
    final out = await DocumentCleaner.clean(
      await widget.pages[index].readAsBytes(),
      mode: mode,
      crop: false,
    );
    if (out != null && mode == _clean) _cleaned[index] = out;
    return out;
  }

  void _ensureCleaned(int index) {
    if (_clean == null ||
        _cleaned.containsKey(index) ||
        _cleaning.contains(index))
      return;
    _cleaning.add(index);
    _cleanPage(index).whenComplete(() {
      _cleaning.remove(index);
      if (mounted) setState(() {});
    });
  }

  void _setClean(CleanMode? mode) {
    setState(() {
      _clean = mode;
      _cleaned.clear();
    });
  }

  /// Saqlash uchun sahifa fayllari: tozalash yoqilgan bo'lsa — tozalangan nusxalar.
  Future<List<File>> _pagesForSave() async {
    if (_clean == null) return widget.pages;
    final tmp = await getTemporaryDirectory();
    final files = <File>[];
    for (var i = 0; i < widget.pages.length; i++) {
      final bytes = await _cleanPage(i);
      if (bytes == null) {
        files.add(widget.pages[i]);
        continue;
      }
      final f = File(
        '${tmp.path}/preview_clean_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
      );
      await f.writeAsBytes(bytes);
      files.add(f);
    }
    return files;
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
        imageFiles: await _pagesForSave(),
        fileName: name,
        quarterTurns: _quarterTurns,
        // Tozalangan sahifalarga qo'shimcha kontrast filtri kerak emas
        enhance: _clean == null && widget.enhance,
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

  Widget _pageImage(int index) {
    final cleaned = _cleaned[index];
    if (cleaned != null) {
      return Image.memory(cleaned, fit: BoxFit.contain, gaplessPlayback: true);
    }
    _ensureCleaned(index);
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.file(widget.pages[index], fit: BoxFit.contain),
        if (_clean != null) const CircularProgressIndicator(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overlayFill = cs.scrim.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
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
                            child: _pageImage(index),
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
                          style: TextStyle(color: cs.onPrimary, fontSize: 13),
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
                SegmentedButton<CleanMode?>(
                  segments: [
                    ButtonSegment(
                      value: null,
                      label: Text('clean_mode_original'.tr()),
                    ),
                    ButtonSegment(
                      value: CleanMode.color,
                      label: Text('clean_mode_color'.tr()),
                    ),
                    ButtonSegment(
                      value: CleanMode.gray,
                      label: Text('clean_mode_gray'.tr()),
                    ),
                    ButtonSegment(
                      value: CleanMode.bw,
                      label: Text('clean_mode_bw'.tr()),
                    ),
                  ],
                  selected: {_clean},
                  showSelectedIcon: false,
                  onSelectionChanged: _generating
                      ? null
                      : (sel) => _setClean(sel.first),
                ),
                const SizedBox(height: 14),
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
                    helperText: _naming
                        ? 'ai_naming'.tr()
                        : (_aiNamed ? 'ai_named'.tr() : null),
                    prefixIcon: _naming
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : (_aiNamed
                              ? Icon(Icons.auto_awesome, color: cs.primary)
                              : null),
                    suffixText: '.pdf',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) {
                    _userEditedName = true;
                    if (_aiNamed) setState(() => _aiNamed = false);
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
