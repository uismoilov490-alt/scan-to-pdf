import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../screens/register_screen.dart';
import '../services/ai_service.dart';
import 'subscription_sheet.dart';

/// AI so'rovi xatosini foydalanuvchiga tushunarli ko'rsatadi:
/// login kerak → kirish oynasi, limit tugadi → Pro taklifi, qolgani → xabar.
Future<void> showAiError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final e = error is AiException
      ? error
      : const AiException('UNKNOWN', '');

  if (e.needsLogin) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: Text('ai_login_title'.tr()),
        content: Text('ai_login_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ai_login_btn'.tr()),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const RegisterScreen()),
      );
    }
    return;
  }

  if (e.quotaExceeded) {
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.hourglass_bottom),
        title: Text('ai_quota_title'.tr()),
        content: Text('ai_quota_body'.tr(
          namedArgs: {'limit': '${e.quota?.limit ?? ''}'},
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('close'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ai_upgrade_btn'.tr()),
          ),
        ],
      ),
    );
    if (upgrade == true && context.mounted) SubscriptionSheet.show(context);
    return;
  }

  final key = switch (e.code) {
    'AI_UNAVAILABLE' => 'ai_err_unavailable',
    'AI_BUSY' => 'ai_err_busy',
    'NETWORK' => 'ai_err_network',
    'AI_REFUSED' => 'ai_err_refused',
    _ => 'ai_err_generic',
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(key.tr()), behavior: SnackBarBehavior.floating),
  );
}
