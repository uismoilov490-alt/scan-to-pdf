import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../tools/tool_catalog.dart';
import '../widgets/tool_tile.dart';

/// "Vositalar" bo'limi: hamma vositalar kategoriyalar bo'yicha.
class ToolsView extends StatelessWidget {
  /// Vosita yopilgandan keyin (yangi fayllar ro'yxatini yangilash uchun)
  final VoidCallback onToolClosed;

  const ToolsView({super.key, required this.onToolClosed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'nav_tools'.tr(),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ),
        for (final MapEntry(key: category, value: tools)
            in ToolCatalog.byCategory.entries)
          if (tools.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 12),
                      child: Text(
                        category.titleKey.tr().toUpperCase(),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    ToolGrid(
                      children: [
                        for (final tool in tools)
                          ToolTile(
                            tool: tool,
                            onTap: () async {
                              await tool.open(context);
                              onToolClosed();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }
}
