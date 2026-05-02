import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_language.dart';
import '../services/api/api_client.dart';
import '../services/pdf_service.dart';
import '../services/user_service.dart';
import 'register_screen.dart';
import 'saved_documents_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'features/overlay_camera_screen.dart';
import 'features/ocr_screen.dart';
import 'features/pdf_edit_screen.dart';
import 'features/pdf_compress_screen.dart';
import 'features/word_to_pdf_screen.dart';
import 'features/pdf_to_word_screen.dart';
import 'features/cyrillic_latin_screen.dart';
import '../widgets/subscription_sheet.dart';

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

  Future<void> _openScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    _loadPdfs();
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

  Future<void> _openTransliteration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CyrillicLatinScreen()),
    );
  }

  Future<void> _openRegister() async {
    Navigator.pop(context);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
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
    await UserService.clearUser();
    await ApiClient.clearTokens();
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
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'pdf_document'.tr(),
    );
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
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
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
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        title: Text(
          'app_title'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _showLanguagePicker,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Text(_selectedLanguage.flag),
              label: Text(_selectedLanguage.shortCode),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildHomeContent(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        icon: const Icon(Icons.document_scanner),
        label: Text('scan'.tr()),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildHomeContent(ThemeData theme) {
    return Column(
      children: [
        _buildFeatureGrid(theme),
        Expanded(
          child: _pdfs.isEmpty ? _buildEmptyState(theme) : _buildPdfList(theme),
        ),
      ],
    );
  }

  Widget _buildFeatureGrid(ThemeData theme) {
    final features = <_QuickFeature>[
      _QuickFeature(
        title: 'feature_document'.tr(),
        icon: Icons.document_scanner_rounded,
        gradientStart: const Color(0xFF1E3A5F),
        gradientEnd: const Color(0xFF3D6BA8),
        onTap: _openScanner,
      ),
      _QuickFeature(
        title: 'feature_passport'.tr(),
        icon: Icons.contact_page_rounded,
        gradientStart: const Color(0xFF134E4A),
        gradientEnd: const Color(0xFF2D6A4F),
        onTap: () => _openOverlayCamera(ScanOverlayMode.passport),
      ),
      _QuickFeature(
        title: 'feature_id_card'.tr(),
        icon: Icons.perm_contact_calendar_rounded,
        gradientStart: const Color(0xFF3730A3),
        gradientEnd: const Color(0xFF6366F1),
        onTap: () => _openOverlayCamera(ScanOverlayMode.idCard),
      ),
      _QuickFeature(
        title: 'feature_extract_text'.tr(),
        icon: Icons.chrome_reader_mode,
        gradientStart: const Color(0xFF92400E),
        gradientEnd: const Color(0xFFD97706),
        onTap: _openOcr,
      ),
      _QuickFeature(
        title: 'feature_pdf_edit'.tr(),
        icon: Icons.picture_as_pdf_rounded,
        gradientStart: const Color(0xFF7F1D1D),
        gradientEnd: const Color(0xFFB91C1C),
        onTap: _openPdfEdit,
      ),
      _QuickFeature(
        title: 'feature_pdf_compress'.tr(),
        icon: Icons.folder_zip_rounded,
        gradientStart: const Color(0xFF0E7490),
        gradientEnd: const Color(0xFF0891B2),
        onTap: _openPdfCompress,
      ),
      _QuickFeature(
        title: 'feature_word_to_pdf'.tr(),
        icon: Icons.article_rounded,
        gradientStart: const Color(0xFF1E3A8A),
        gradientEnd: const Color(0xFF2563EB),
        onTap: _openWordToPdf,
      ),
      _QuickFeature(
        title: 'feature_pdf_to_word'.tr(),
        icon: Icons.import_export_rounded,
        gradientStart: const Color(0xFF064E3B),
        gradientEnd: const Color(0xFF059669),
        onTap: _openPdfToWord,
      ),
      _QuickFeature(
        title: 'translit_feature'.tr(),
        icon: Icons.translate_rounded,
        gradientStart: const Color(0xFF5B21B6),
        gradientEnd: const Color(0xFF7C3AED),
        onTap: _openTransliteration,
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.55 : 0.35,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.45 : 0.06,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: theme.colorScheme.primary.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.12 : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: features.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.88,
        ),
        itemBuilder: (context, index) {
          return _ProFeatureTile(feature: features[index]);
        },
      ),
    );
  }

  Widget _buildAppDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _user == null ? _openRegister : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.86),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      _UserAvatar(user: _user),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _user != null
                                  ? _user!.displayIdentifier
                                  : 'drawer_login_profile'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DrawerMenuTile(
              icon: Icons.workspace_premium_rounded,
              title: 'profile_my_subscriptions'.tr(),
              subtitle: 'profile_my_subscriptions_subtitle'.tr(),
              onTap: () {
                Navigator.pop(context);
                _openSubscriptionsSheet();
              },
            ),
            _DrawerMenuTile(
              icon: Icons.folder_special_rounded,
              title: 'profile_saved_documents'.tr(),
              subtitle: 'profile_saved_documents_subtitle'.tr(),
              onTap: _openSavedDocuments,
            ),
            _DrawerMenuTile(
              icon: Icons.logout_rounded,
              title: 'profile_logout'.tr(),
              subtitle: 'profile_logout_subtitle'.tr(),
              onTap: _signOut,
            ),
            _DrawerMenuTile(
              icon: Icons.settings_outlined,
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
            _DrawerMenuTile(
              icon: Icons.share_outlined,
              title: 'drawer_share'.tr(),
              subtitle: 'drawer_share_subtitle'.tr(),
              onTap: () => Navigator.pop(context),
            ),
            _DrawerMenuTile(
              icon: Icons.description_outlined,
              title: 'drawer_terms'.tr(),
              subtitle: 'drawer_terms_subtitle'.tr(),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 90,
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 20),
          Text(
            'no_documents'.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'no_documents_hint'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pdfs.length,
      itemBuilder: (context, index) {
        final file = _pdfs[index];
        final stat = file.statSync();
        final name = file.path.split('/').last.replaceAll('.pdf', '');
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _viewPdf(file),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf,
                      color: theme.colorScheme.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(stat.modified),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatSize(stat.size),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (val) {
                      if (val == 'view') _viewPdf(file);
                      if (val == 'share') _sharePdf(file);
                      if (val == 'delete') _deletePdf(file);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'view',
                        child: ListTile(
                          leading: const Icon(Icons.visibility),
                          title: Text('view'.tr()),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: const Icon(Icons.share),
                          title: Text('share'.tr()),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete, color: Colors.red),
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
          ),
        );
      },
    );
  }
}

class _DrawerMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DrawerMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _QuickFeature {
  final String title;
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;
  final VoidCallback onTap;

  _QuickFeature({
    required this.title,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
    required this.onTap,
  });
}

/// Premium grid tile: gradient gem-style icon chip + restrained typography.
class _ProFeatureTile extends StatelessWidget {
  final _QuickFeature feature;

  const _ProFeatureTile({required this.feature});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final shadowColor = Color.lerp(
      feature.gradientEnd,
      Colors.black,
      isDark ? 0.55 : 0.35,
    )!;
    final highlight = Color.lerp(
      feature.gradientStart,
      isDark ? cs.surface : Colors.white,
      isDark ? 0.14 : 0.08,
    )!;
    final rim = (isDark ? cs.onPrimary : Colors.white).withValues(
      alpha: isDark ? 0.18 : 0.28,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: feature.onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: feature.gradientEnd.withValues(alpha: 0.12),
        highlightColor: feature.gradientEnd.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      highlight,
                      feature.gradientEnd,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor.withValues(alpha: isDark ? 0.5 : 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                      spreadRadius: -2,
                    ),
                  ],
                  border: Border.all(
                    color: rim,
                    width: 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 7,
                      left: 10,
                      child: IgnorePointer(
                        child: Container(
                          width: 22,
                          height: 11,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.42),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      feature.icon,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.96),
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                feature.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: 0.15,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final UserData? user;

  const _UserAvatar({this.user});

  @override
  Widget build(BuildContext context) {
    if (user?.photoUrl != null) {
      return ClipOval(
        child: Image.network(
          user!.photoUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, st) => _defaultAvatar(),
        ),
      );
    }
    if (user != null && user!.name.isNotEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          user!.name[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 28),
    );
  }
}

