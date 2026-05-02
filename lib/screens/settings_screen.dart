import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_language.dart';
import '../providers/app_settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _ellipsisPath(String path, {int max = 54}) {
    if (path.length <= max) return path;
    final half = max ~/ 2 - 1;
    return '${path.substring(0, half)}…${path.substring(path.length - half)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('settings_title'.tr()),
        backgroundColor: cs.surfaceContainerLow,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'settings_section_display'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'settings_theme'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Consumer<AppSettingsController>(
                  builder: (context, settings, _) {
                    return SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('settings_theme_system'.tr()),
                          icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('settings_theme_light'.tr()),
                          icon: const Icon(Icons.light_mode_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('settings_theme_dark'.tr()),
                          icon: const Icon(Icons.dark_mode_rounded, size: 18),
                        ),
                      ],
                      selected: {settings.themeMode},
                      multiSelectionEnabled: false,
                      emptySelectionAllowed: false,
                      showSelectedIcon: false,
                      onSelectionChanged: (next) {
                        settings.setThemeMode(next.first);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'settings_section_language'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.language_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'settings_language'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'settings_language_hint'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...AppLanguage.values.map((lang) {
                  final selected =
                      AppLanguage.fromLocale(context.locale) == lang;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected
                          ? cs.primaryContainer.withValues(alpha: 0.55)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await context.setLocale(lang.locale);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'language_changed'.tr(
                                  namedArgs: {'title': lang.title},
                                ),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Text(lang.flag, style: const TextStyle(fontSize: 22)),
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
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? cs.primary
                                    : cs.outlineVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'settings_section_storage'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Consumer<AppSettingsController>(
            builder: (context, settings, _) {
              final custom = settings.customPdfDirectory;
              final displayPath = custom != null
                  ? _ellipsisPath(custom)
                  : 'settings_save_location_default'.tr();

              return _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.folder_special_rounded,
                            color: cs.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'settings_save_location'.tr(),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'settings_save_location_hint'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file_outlined,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          displayPath,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () async {
                              final picked =
                                  await FilePicker.platform.getDirectoryPath();
                              if (picked == null || !context.mounted) return;
                              try {
                                await context
                                    .read<AppSettingsController>()
                                    .setCustomPdfDirectory(picked);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('settings_folder_updated'.tr()),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('settings_invalid_folder'.tr()),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.folder_open_rounded, size: 20),
                            label: Text('settings_choose_folder'.tr()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          tooltip: 'settings_use_default_folder'.tr(),
                          onPressed: settings.usesDefaultPdfDirectory
                              ? null
                              : () async {
                                  await settings.setCustomPdfDirectory(null);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'settings_folder_reset'.tr(),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.restore_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.55 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
