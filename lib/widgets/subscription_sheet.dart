import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../providers/subscription_provider.dart';

class SubscriptionSheet extends StatelessWidget {
  const SubscriptionSheet({super.key});

  static void show(BuildContext context) {
    final provider = context.read<SubscriptionProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const SubscriptionSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, cs, sub),
            const SizedBox(height: 20),
            _FreePlanCard(isActive: !sub.isPro),
            const SizedBox(height: 12),
            _buildProSection(sub, cs),
            if (sub.error != null) ...[
              const SizedBox(height: 12),
              Text(
                sub.error!,
                style: TextStyle(color: cs.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            if (!sub.isPro && sub.storeAvailable && !sub.loadingProducts) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: sub.purchasing ? null : sub.restorePurchases,
                  child: Text(
                    'sub_restore_purchases'.tr(),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme cs,
    SubscriptionProvider sub,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'profile_subscription_sheet_title'.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (sub.isPro)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'sub_pro_active'.tr(),
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProSection(SubscriptionProvider sub, ColorScheme cs) {
    if (sub.loadingProducts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!sub.storeAvailable) {
      return _InfoCard(
        message: 'sub_store_unavailable'.tr(),
        color: cs.errorContainer.withValues(alpha: 0.4),
        textColor: cs.onErrorContainer,
      );
    }

    if (sub.products.isEmpty) {
      return _InfoCard(
        message: 'sub_products_not_found'.tr(),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        textColor: cs.onSurfaceVariant,
      );
    }

    final savings = _calcSavings(sub);
    return Column(
      children: [
        if (sub.monthlyProduct != null)
          _ProPlanCard(
            product: sub.monthlyProduct!,
            label: 'sub_monthly'.tr(),
            isPro: sub.isPro,
            purchasing: sub.purchasing,
            onBuy: () => sub.buyProduct(sub.monthlyProduct!),
          ),
        if (sub.monthlyProduct != null && sub.yearlyProduct != null)
          const SizedBox(height: 12),
        if (sub.yearlyProduct != null)
          _ProPlanCard(
            product: sub.yearlyProduct!,
            label: 'sub_yearly'.tr(),
            savings: savings,
            isPro: sub.isPro,
            purchasing: sub.purchasing,
            onBuy: () => sub.buyProduct(sub.yearlyProduct!),
          ),
      ],
    );
  }

  String? _calcSavings(SubscriptionProvider sub) {
    final m = sub.monthlyProduct;
    final y = sub.yearlyProduct;
    if (m == null || y == null || m.rawPrice == 0) return null;
    final pct = ((m.rawPrice * 12 - y.rawPrice) / (m.rawPrice * 12) * 100)
        .round();
    if (pct <= 0) return null;
    return 'sub_save_percent'.tr(namedArgs: {'percent': '$pct'});
  }
}

class _FreePlanCard extends StatelessWidget {
  final bool isActive;

  const _FreePlanCard({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isActive
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile_plan_free'.tr(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'profile_plan_free_desc'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'profile_plan_current'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProPlanCard extends StatelessWidget {
  final ProductDetails product;
  final String label;
  final String? savings;
  final bool isPro;
  final bool purchasing;
  final VoidCallback onBuy;

  const _ProPlanCard({
    required this.product,
    required this.label,
    this.savings,
    required this.isPro,
    required this.purchasing,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPro
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: isPro
            ? Border.all(
                color: cs.primary.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'profile_plan_pro'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    _Badge(
                      text: label,
                      bg: cs.secondaryContainer,
                      fg: cs.onSecondaryContainer,
                    ),
                    if (savings != null)
                      _Badge(
                        text: savings!,
                        bg: const Color(0xFF2E7D32),
                        fg: Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.price,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                Text(
                  'profile_plan_pro_desc'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isPro)
            Icon(Icons.check_circle_rounded, color: cs.primary, size: 28)
          else
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: purchasing ? null : onBuy,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: purchasing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Text('sub_buy_btn'.tr()),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _Badge({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String message;
  final Color color;
  final Color textColor;

  const _InfoCard({
    required this.message,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: TextStyle(color: textColor, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
