import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_language.dart';
import '../services/pdf_service.dart';
import '../services/user_service.dart';
import 'register_screen.dart';
import 'saved_documents_screen.dart';
import 'preview_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'features/overlay_camera_screen.dart';
import 'features/ocr_screen.dart';
import 'features/pdf_edit_screen.dart';
import 'features/pdf_compress_screen.dart';
import 'features/word_to_pdf_screen.dart';
import 'features/pdf_to_word_screen.dart';
import 'features/cyrillic_latin_screen.dart';
import 'features/image_convert_screen.dart';
import 'features/translate_screen.dart';
import 'features/document_clean_screen.dart';
import '../widgets/subscription_sheet.dart';
import '../services/ad_service.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _pdfs = [];
  bool _loading = true;
  AppLanguage _selectedLanguage = AppLanguage.uzbek;
  UserData? _user;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLanguage = AppLanguage.fromLocale(context.locale);
  }

  @override
  void initState() {
    super.initState();
    _loadPdfs();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await UserService.getUser();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _loadPdfs() async {
    final files = await PdfService.listSavedPdfs();
    if (mounted) {
      setState(() {
        _pdfs = files;
        _loading = false;
      });
    }
  }

  /// Hujjat skaneri: Google ML Kit (varaq chetini topadi, qiyshiqni to'g'rilaydi,
  /// dog'/soyani AI bilan tozalaydi). Qurilmada ishlamasa — oddiy kamera skaneri.
  Future<void> _openScanner() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        pageLimit: 50,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final pages = (result.images ?? []).map(File.new).toList();
      debugPrint('[scanner] ${pages.length} sahifa qaytdi, mounted=$mounted');
      if (pages.isEmpty || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PreviewScreen(pages: pages, enhance: false, autoClean: true),
        ),
      );
    } on PlatformException catch (e) {
      if ((e.message ?? '').contains('cancelled'))
        return; // foydalanuvchi bekor qildi
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );
    } finally {
      scanner.close();
      _loadPdfs();
    }
  }

  Future<void> _openOverlayCamera(ScanOverlayMode mode) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OverlayCameraScreen(mode: mode)),
    );
    if (result == true) _loadPdfs();
  }

  Future<void> _openOcr() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OcrScreen()),
    );
  }

  Future<void> _openPdfEdit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PdfEditScreen()),
    );
    if (result == true) _loadPdfs();
  }

  Future<void> _openPdfCompress() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PdfCompressScreen()),
    );
    _loadPdfs();
  }

  Future<void> _openWordToPdf() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WordToPdfScreen()),
    );
    _loadPdfs();
  }

  Future<void> _openPdfToWord() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PdfToWordScreen()),
    );
  }

  Future<void> _openClean() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DocumentCleanScreen()),
    );
    await _loadPdfs();
  }

  Future<void> _openTranslate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TranslateScreen()),
    );
  }

  /// "Rasm konvertori": 5 ta rasm formati funksiyasidan birini tanlash.
  Future<void> _openImageConverters() async {
    final items = <(ConvertMode, IconData, Color, String)>[
      (
        ConvertMode.jpgToPdf,
        Icons.picture_as_pdf_rounded,
        const Color(0xFFDB2777),
        'conv_hint_jpg_to_pdf',
      ),
      (
        ConvertMode.pdfToJpg,
        Icons.image_rounded,
        const Color(0xFFEA580C),
        'conv_hint_pdf_to_jpg',
      ),
      (
        ConvertMode.webpToJpg,
        Icons.public_rounded,
        const Color(0xFF0EA5E9),
        'conv_hint_webp_to_jpg',
      ),
      (
        ConvertMode.pngToJpg,
        Icons.transform_rounded,
        const Color(0xFF65A30D),
        'conv_hint_png_to_jpg',
      ),
      (
        ConvertMode.jpgToPng,
        Icons.wallpaper_rounded,
        const Color(0xFF8B5CF6),
        'conv_hint_jpg_to_png',
      ),
    ];
    final mode = await showModalBottomSheet<ConvertMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'feature_image_converter'.tr(),
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (m, icon, color, hint) in items)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                title: Text(
                  m.titleKey.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(hint.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode != null) await _openConverter(mode);
  }

  Future<void> _openConverter(ConvertMode mode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImageConvertScreen(mode: mode)),
    );
    await _loadPdfs();
  }

  Future<void> _openTransliteration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CyrillicLatinScreen()),
    );
    await _loadPdfs();
  }

  Future<void> _openRegister() async {
    Navigator.pop(context);
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const RegisterScreen()));
    if (mounted) _loadUser();
  }

  void _openSubscriptionsSheet() => SubscriptionSheet.show(context);

  Future<void> _openSavedDocuments() async {
    Navigator.pop(context);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SavedDocumentsScreen()),
    );
    if (mounted) _loadPdfs();
  }

  Future<void> _signOut() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('profile_not_logged_in'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('profile_logout_confirm_title'.tr()),
        content: Text('profile_logout_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('profile_logout'.tr()),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    Navigator.pop(context);
    await UserService.signOut();
    if (!mounted) return;
    setState(() => _user = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('profile_logout_success'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _viewPdf(File file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              file.path.split('/').last.replaceAll('.pdf', ''),
              style: const TextStyle(fontSize: 15),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _sharePdf(file),
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) => bytes,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
          ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'pdf_document'.tr());
  }

  Future<void> _deletePdf(File file) async {
    final name = file.path.split('/').last.replaceAll('.pdf', '');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_title'.tr()),
        content: Text('delete_confirm'.tr(namedArgs: {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PdfService.deletePdf(file.path);
      _loadPdfs();
    }
  }

  String _formatDate(DateTime dt) => DateFormat('dd.MM.yyyy  HH:mm').format(dt);

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Cursor yozgan bottom sheet UI — lokalizatsiya + setLocale ulanadi
  Future<void> _showLanguagePicker() async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            AppLanguage current = _selectedLanguage;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'language_title'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'language_subtitle'.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...AppLanguage.values.map((lang) {
                      final isSelected = current == lang;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setModalState(() => current = lang);
                            Navigator.pop(ctx, lang);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  lang.flag,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        lang.subtitle,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _selectedLanguage = selected);
      await context.setLocale(selected.locale);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'language_changed'.tr(namedArgs: {'title': selected.title}),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: _buildAppDrawer(theme),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildHomeContent(theme),
      ),
      bottomNavigationBar: const AdBanner(),
      floatingActionButton: _ScanFab(onPressed: _openScanner),
    );
  }

  // Sarlavha, funksiyalar va so'nggi fayllar bitta umumiy scroll'da.
  Widget _buildHomeContent(ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(theme)),
        SliverToBoxAdapter(child: _buildFeatureGrid(theme)),
        if (_pdfs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(theme),
          )
        else
          _buildPdfList(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Builder(
                builder: (ctx) => IconButton(
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  icon: const Icon(Icons.menu_rounded, size: 28),
                ),
              ),
              const Spacer(),
              Material(
                color: cs.surfaceContainerLow,
                shape: StadiumBorder(
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _showLanguagePicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.language_rounded,
                          size: 20,
                          color: cs.onSurface,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedLanguage.shortCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'app_title'.tr(),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 13, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'home_ai_powered'.tr(),
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _SmartScanCard(onTap: _openScanner),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureGrid(ThemeData theme) {
    // 1-qator: skanerlash; 2-qator: AI funksiyalari; qolganlari — oflayn vositalar.
    final features = <_QuickFeature>[
      _QuickFeature(
        title: 'feature_document'.tr(),
        icon: Icons.document_scanner_outlined,
        color: const Color(0xFF0A84FF),
        onTap: _openScanner,
      ),
      _QuickFeature(
        title: 'feature_passport'.tr(),
        icon: Icons.badge_outlined,
        color: const Color(0xFF0066CC),
        onTap: () => _openOverlayCamera(ScanOverlayMode.passport),
      ),
      _QuickFeature(
        title: 'feature_id_card'.tr(),
        icon: Icons.credit_card_outlined,
        color: const Color(0xFF5856D6),
        onTap: () => _openOverlayCamera(ScanOverlayMode.idCard),
      ),
      _QuickFeature(
        title: 'feature_extract_text'.tr(),
        icon: Icons.text_snippet_outlined,
        color: const Color(0xFFFF9500),
        onTap: _openOcr,
        ai: true,
      ),
      _QuickFeature(
        title: 'translit_feature_both'.tr(),
        label: 'Я⇄A',
        color: const Color(0xFFAF52DE),
        onTap: _openTransliteration,
        ai: true,
      ),
      _QuickFeature(
        title: 'feature_translate'.tr(),
        icon: Icons.language_rounded,
        color: const Color(0xFFBF5AF2),
        onTap: _openTranslate,
        ai: true,
      ),
      _QuickFeature(
        title: 'feature_clean'.tr(),
        icon: Icons.auto_fix_high_outlined,
        color: const Color(0xFF32ADE6),
        onTap: _openClean,
      ),
      _QuickFeature(
        title: 'feature_pdf_edit'.tr(),
        icon: Icons.edit_document,
        color: const Color(0xFFFF3B30),
        onTap: _openPdfEdit,
      ),
      _QuickFeature(
        title: 'feature_pdf_compress'.tr(),
        icon: Icons.compress_rounded,
        color: const Color(0xFF30B0C7),
        onTap: _openPdfCompress,
      ),
      _QuickFeature(
        title: 'feature_word_to_pdf'.tr(),
        icon: Icons.description_outlined,
        color: const Color(0xFF34C759),
        onTap: _openWordToPdf,
      ),
      _QuickFeature(
        title: 'feature_pdf_to_word'.tr(),
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF248A3D),
        onTap: _openPdfToWord,
      ),
      _QuickFeature(
        title: 'feature_image_converter'.tr(),
        icon: Icons.image_outlined,
        color: const Color(0xFFFFCC00),
        iconColor: const Color(0xFF1C1C1E),
        onTap: _openImageConverters,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: features.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 10,
          childAspectRatio: 1.02,
        ),
        itemBuilder: (context, index) => _FeatureTile(feature: features[index]),
      ),
    );
  }

  Widget _buildAppDrawer(ThemeData theme) {
    final cs = theme.colorScheme;
    final isPro = context.watch<SubscriptionProvider>().isPro;
    final width = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: width * 0.88,
      backgroundColor: cs.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            // Hisob
            _MenuGroup(
              children: [
                InkWell(
                  onTap: _user == null ? _openRegister : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _UserAvatar(user: _user),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _user != null
                                    ? _user!.displayIdentifier
                                    : 'drawer_account'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _user != null
                                    ? _user!.name
                                    : 'drawer_guest_user'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_user == null)
                          Icon(Icons.chevron_right_rounded, color: cs.outline),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PremiumCard(
              isPro: isPro,
              onTap: () {
                Navigator.pop(context);
                _openSubscriptionsSheet();
              },
            ),
            const SizedBox(height: 16),
            _MenuGroup(
              children: [
                _MenuRow(
                  icon: Icons.folder_outlined,
                  tint: const Color(0xFF0A84FF),
                  title: 'profile_saved_documents'.tr(),
                  subtitle: 'profile_saved_documents_subtitle'.tr(),
                  onTap: _openSavedDocuments,
                ),
                _MenuRow(
                  icon: Icons.tune_rounded,
                  tint: const Color(0xFF8E8E93),
                  title: 'settings_title'.tr(),
                  subtitle: 'settings_drawer_subtitle'.tr(),
                  onTap: () {
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (!context.mounted) return;
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      if (context.mounted) _loadPdfs();
                    });
                  },
                ),
                _MenuRow(
                  icon: Icons.share_outlined,
                  tint: const Color(0xFF34C759),
                  title: 'drawer_share'.tr(),
                  subtitle: 'drawer_share_subtitle'.tr(),
                  onTap: () => Navigator.pop(context),
                ),
                _MenuRow(
                  icon: Icons.description_outlined,
                  tint: const Color(0xFF8E8E93),
                  title: 'drawer_terms'.tr(),
                  subtitle: 'drawer_terms_subtitle'.tr(),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_user != null) ...[
              const SizedBox(height: 16),
              _MenuGroup(
                children: [
                  _MenuRow(
                    icon: Icons.logout_rounded,
                    tint: const Color(0xFFFF3B30),
                    title: 'profile_logout'.tr(),
                    subtitle: 'profile_logout_subtitle'.tr(),
                    danger: true,
                    showChevron: false,
                    onTap: _signOut,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    // Pastdagi "Skanerlash" tugmasi yozuvni to'smasligi uchun joy qoldiramiz
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              'no_documents'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'no_documents_hint'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.85,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfList(ThemeData theme) {
    final cs = theme.colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(
              'home_recent'.tr(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          _MenuGroup(
            children: [for (final file in _pdfs) _pdfRow(theme, file)],
          ),
        ],
      ),
    );
  }

  Widget _pdfRow(ThemeData theme, File file) {
    final cs = theme.colorScheme;
    final stat = file.statSync();
    final name = file.path.split('/').last;
    return InkWell(
      onTap: () => _viewPdf(file),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.insert_drive_file_outlined,
                color: Color(0xFFFF3B30),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatDate(stat.modified)} · ${_formatSize(stat.size)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: cs.outline),
              onSelected: (val) {
                if (val == 'view') _viewPdf(file);
                if (val == 'share') _sharePdf(file);
                if (val == 'delete') _deletePdf(file);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: Text('view'.tr()),
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: Text('share'.tr()),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: Text(
                      'delete'.tr(),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "AI Smart Scan" — asosiy skanerni ochuvchi katta karta.
class _SmartScanCard extends StatelessWidget {
  final VoidCallback onTap;

  const _SmartScanCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home_smart_title'.tr(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'home_smart_desc'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastdagi ko'k "Skanerlash" tugmasi.
class _ScanFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _ScanFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.center_focus_weak_rounded),
        label: Text(
          'scan'.tr(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Oq, yumaloq burchakli guruh (ichidagi qatorlar orasida chiziq).
class _MenuGroup extends StatelessWidget {
  final List<Widget> children;

  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0)
        items.add(
          Divider(height: 1, thickness: 1, color: cs.surfaceContainerHigh),
        );
      items.add(children[i]);
    }
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool showChevron;

  const _MenuRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: danger ? tint : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (showChevron)
              Icon(Icons.chevron_right_rounded, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

/// Menyudagi oltin rangli Premium kartasi.
class _PremiumCard extends StatelessWidget {
  final bool isPro;
  final VoidCallback onTap;

  const _PremiumCard({required this.isPro, required this.onTap});

  static const gold = Color(0xFFE8C774);
  static const goldDark = Color(0xFFD4B261);
  static const brown = Color(0xFF4A3216);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: gold,
      borderRadius: BorderRadius.circular(24),
      elevation: 6,
      shadowColor: gold.withValues(alpha: 0.6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: goldDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: brown,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (isPro ? 'drawer_premium_active' : 'drawer_premium').tr(),
                      style: const TextStyle(
                        color: brown,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'drawer_premium_desc'.tr(),
                      style: TextStyle(
                        color: brown.withValues(alpha: 0.75),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: brown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  (isPro ? 'drawer_manage' : 'drawer_upgrade').tr(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickFeature {
  final String title;
  final IconData? icon;

  /// Ikonka o'rniga matn (masalan "Я⇄A")
  final String? label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  /// AI (server) ishlatadigan funksiya — ikonkada yulduzcha belgisi chiqadi
  final bool ai;

  _QuickFeature({
    required this.title,
    required this.color,
    required this.onTap,
    this.icon,
    this.label,
    this.iconColor = Colors.white,
    this.ai = false,
  });
}

class _FeatureTile extends StatelessWidget {
  final _QuickFeature feature;

  const _FeatureTile({required this.feature});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: feature.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: feature.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: feature.label != null
                    ? Text(
                        feature.label!,
                        style: TextStyle(
                          color: feature.iconColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Icon(feature.icon, color: feature.iconColor, size: 30),
              ),
              if (feature.ai)
                Positioned(
                  top: -7,
                  right: -7,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: feature.color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            feature.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final UserData? user;

  const _UserAvatar({this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (user?.photoUrl != null) {
      return ClipOval(
        child: Image.network(
          user!.photoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, st) => _defaultAvatar(cs),
        ),
      );
    }
    if (user != null && user!.name.isNotEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          user!.name[0].toUpperCase(),
          style: TextStyle(
            color: cs.primary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return _defaultAvatar(cs);
  }

  Widget _defaultAvatar(ColorScheme cs) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline_rounded,
        color: cs.onSurfaceVariant,
        size: 28,
      ),
    );
  }
}
