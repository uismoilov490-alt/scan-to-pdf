import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/subscription_provider.dart';
import '../screens/register_screen.dart';
import '../services/subscription_service.dart';

/// "Obunalarim": Bepul va Oylik tariflar, obunani boshqarish va xaridlarni
/// tiklash. Limit raqamlari foydalanuvchiga ataylab ko'rsatilmaydi.
class SubscriptionSheet extends StatelessWidget {
  const SubscriptionSheet({super.key});

  // Oylik tarif kartasi (dizayn: Subscription.pdf)
  static const gold = Color(0xFFE8C774);
  static const brown = Color(0xFF4A3216);

  static void show(BuildContext context) {
    final provider = context.read<SubscriptionProvider>();
    provider.refreshAccount();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => SafeArea(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(
              'profile_subscription_sheet_title'.tr(),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            _StatusCard(sub: sub),
            const SizedBox(height: 16),
            _PlanCard(
              title: 'profile_plan_free'.tr(),
              price: 'sub_free_price'.tr(),
              features: [
                'sub_feat_offline'.tr(),
                'sub_feat_free_ai'.tr(),
                'sub_feat_ads'.tr(),
              ],
              active: !sub.isPro,
            ),
            const SizedBox(height: 16),
            _PlanCard(
              title: 'sub_monthly'.tr(),
              badge: 'sub_best_value'.tr(),
              price:
                  '${sub.monthlyProduct?.price ?? SubscriptionService.monthlyFallbackPrice} ${'sub_per_month'.tr()}',
              features: [
                'sub_feat_offline'.tr(),
                'sub_feat_monthly_ai'.tr(),
                'sub_feat_no_ads'.tr(),
              ],
              active: sub.isPro,
              gold: true,
              action: _buyButton(context, sub, sub.monthlyProduct),
            ),
            if (sub.error != null) ...[
              const SizedBox(height: 12),
              Text(
                sub.error == 'sub_login_to_link'
                    ? 'sub_login_to_link'.tr()
                    : sub.error!,
                style: TextStyle(color: cs.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            if (!sub.loadingProducts &&
                (!sub.storeAvailable || sub.products.isEmpty)) ...[
              const SizedBox(height: 12),
              Text(
                (sub.storeAvailable
                        ? 'sub_products_not_found'
                        : 'sub_store_unavailable')
                    .tr(),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            if (sub.isPro && sub.proUntil != null)
              OutlinedButton.icon(
                onPressed: _manage,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text('sub_manage'.tr()),
              ),
            if (sub.storeAvailable)
              TextButton(
                onPressed: sub.purchasing ? null : sub.restorePurchases,
                child: Text(
                  'sub_restore_purchases'.tr(),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            Text(
              'sub_terms_note'.tr(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buyButton(
    BuildContext context,
    SubscriptionProvider sub,
    ProductDetails? product,
  ) {
    if (sub.isPro) return null;
    return FilledButton(
      onPressed: product == null || sub.purchasing
          ? null
          : () {
              if (!sub.signedIn) {
                // Xarid server tomonda hisobga bog'lanadi — avval kirish kerak
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                );
                return;
              }
              sub.buyProduct(product);
            },
      style: FilledButton.styleFrom(
        backgroundColor: brown,
        foregroundColor: Colors.white,
        disabledBackgroundColor: brown.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      child: sub.purchasing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text('sub_buy_btn'.tr()),
    );
  }

  Future<void> _manage() async {
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions'
      '?sku=${SubscriptionService.proMonthlyId}'
      '&package=${SubscriptionService.androidPackage}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Joriy holat: kirmagan bo'lsa — kirish taklifi, oylik tarifda — keyingi
/// to'lov sanasi. Limit raqamlari ko'rsatilmaydi.
class _StatusCard extends StatelessWidget {
  final SubscriptionProvider sub;

  const _StatusCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      color: cs.onPrimaryContainer,
      fontSize: 14.5,
      height: 1.4,
    );
    final Widget child;
    if (!sub.signedIn) {
      child = Row(
        children: [
          Expanded(child: Text('sub_login_to_see'.tr(), style: textStyle)),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegisterScreen()),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: cs.surfaceContainerLow,
              foregroundColor: cs.primary,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text('ai_login_btn'.tr()),
          ),
        ],
      );
    } else {
      final until = sub.proUntil;
      final text = !sub.isPro
          ? 'sub_status_free'.tr()
          : until == null
          ? 'sub_status_pro'.tr()
          : 'sub_status_pro_until'.tr(
              namedArgs: {'date': DateFormat('dd.MM.yyyy').format(until)},
            );
      child = Row(
        children: [
          Icon(
            sub.isPro ? Icons.workspace_premium_rounded : Icons.auto_awesome,
            color: cs.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: textStyle)),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? badge;
  final List<String> features;
  final bool active;
  final bool gold;
  final Widget? action;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.features,
    required this.active,
    this.badge,
    this.gold = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const brown = SubscriptionSheet.brown;
    final fg = gold ? brown : cs.onSurface;
    final accent = gold ? brown : cs.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: gold ? SubscriptionSheet.gold : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        boxShadow: gold
            ? [
                BoxShadow(
                  color: SubscriptionSheet.gold.withValues(alpha: 0.55),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: fg,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 10),
                _Badge(
                  text: badge!,
                  bg: gold ? brown : cs.primary,
                  fg: Colors.white,
                ),
              ],
              const Spacer(),
              if (active)
                _Badge(
                  text: 'profile_plan_current'.tr(),
                  bg: gold ? Colors.white.withValues(alpha: 0.6) : cs.primary,
                  fg: gold ? brown : cs.onPrimary,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 12),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 20, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(fontSize: 15, height: 1.35, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          if (action != null && !active) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 54, child: action),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
