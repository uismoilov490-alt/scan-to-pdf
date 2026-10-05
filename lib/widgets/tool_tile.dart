import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../tools/tool_catalog.dart';

/// Vosita ikonkasi: rangli kvadrat + nom; AI vositalarida yulduzcha belgisi.
class ToolTile extends StatelessWidget {
  final Tool tool;
  final VoidCallback onTap;

  const ToolTile({super.key, required this.tool, required this.onTap});

  @override
  Widget build(BuildContext context) => ToolTileView(
    title: tool.titleKey.tr(),
    color: tool.color,
    icon: tool.icon,
    label: tool.label,
    iconColor: tool.iconColor,
    ai: tool.ai,
    onTap: onTap,
  );
}

/// Katalogga bog'lanmagan ikonka (masalan "Barcha vositalar").
class ToolTileView extends StatelessWidget {
  final String title;
  final Color color;
  final IconData? icon;
  final String? label;
  final Color iconColor;
  final bool ai;
  final VoidCallback onTap;

  const ToolTileView({
    super.key,
    required this.title,
    required this.color,
    required this.onTap,
    this.icon,
    this.label,
    this.iconColor = Colors.white,
    this.ai = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: label != null
                    ? Text(
                        label!,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 29),
              ),
              if (ai)
                Positioned(
                  top: -7,
                  right: -7,
                  child: Container(
                    width: 25,
                    height: 25,
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
                    child: Icon(Icons.auto_awesome, size: 14, color: color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
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

/// 3 ustunli vositalar to'ri (bosh sahifa va "Vositalar" uchun umumiy).
class ToolGrid extends StatelessWidget {
  final List<Widget> children;

  const ToolGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    crossAxisSpacing: 8,
    mainAxisSpacing: 10,
    childAspectRatio: 1.0,
    children: children,
  );
}
