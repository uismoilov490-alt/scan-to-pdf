import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/user_service.dart';
import '../widgets/ai_error.dart';
import 'register_screen.dart';
import 'saved_documents_screen.dart';
import '../widgets/subscription_sheet.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserData? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await UserService.getUser();
    if (mounted) {
      setState(() {
        _user = user;
        _loading = false;
      });
    }
  }

  Future<void> _openRegister() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _logout() async {
    final logged = _user != null;
    if (!logged) {
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text('profile_logout'.tr()),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await UserService.signOut();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(
        content: Text('profile_logout_success'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Theme.of(ctx).colorScheme.error),
        title: Text('profile_delete_confirm_title'.tr()),
        content: Text('profile_delete_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text('profile_delete_account'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await UserService.deleteAccount();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Xavfsizlik uchun Firebase yaqinda kirishni talab qiladi
        await UserService.signOut();
        messenger.showSnackBar(SnackBar(
          content: Text('profile_delete_relogin'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        if (mounted) Navigator.pop(context, true);
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text('error_prefix'.tr(namedArgs: {'message': e.message ?? e.code})),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    } on AiException catch (e) {
      if (mounted) await showAiError(context, e);
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true);
    messenger.showSnackBar(SnackBar(
      content: Text('profile_delete_success'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _openSubscriptionsSheet() => SubscriptionSheet.show(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('profile_title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = _user;
    final isGuest = user == null;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary,
                      Color.lerp(cs.primary, cs.surfaceContainerHighest, 0.42)!,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: Row(
                      children: [
                        _ProfileAvatar(user: user),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isGuest
                                    ? 'drawer_guest_user'.tr()
                                    : user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isGuest
                                    ? 'profile_guest_hint'.tr()
                                    : user.displayIdentifier,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onPrimary.withValues(alpha: 0.88),
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                              if (isGuest) ...[
                                const SizedBox(height: 10),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    foregroundColor: cs.onPrimary,
                                    backgroundColor: cs.onPrimary
                                        .withValues(alpha: 0.18),
                                  ),
                                  onPressed: _openRegister,
                                  child: Text('profile_login_register_btn'.tr()),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'profile_section_actions'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.workspace_premium_rounded,
                    iconColor: const Color(0xFFC9A227),
                    title: 'profile_my_subscriptions'.tr(),
                    subtitle: 'profile_my_subscriptions_subtitle'.tr(),
                    onTap: _openSubscriptionsSheet,
                  ),
                  const SizedBox(height: 10),
                  _ProfileActionTile(
                    icon: Icons.folder_special_rounded,
                    iconColor: cs.primary,
                    title: 'profile_saved_documents'.tr(),
                    subtitle: 'profile_saved_documents_subtitle'.tr(),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedDocumentsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _ProfileActionTile(
                    icon: Icons.logout_rounded,
                    iconColor: cs.error,
                    title: 'profile_logout'.tr(),
                    subtitle: 'profile_logout_subtitle'.tr(),
                    dense: true,
                    onTap: _logout,
                  ),
                  if (_user != null) ...[
                    const SizedBox(height: 10),
                    _ProfileActionTile(
                      icon: Icons.delete_forever_rounded,
                      iconColor: cs.error,
                      title: 'profile_delete_account'.tr(),
                      subtitle: 'profile_delete_account_subtitle'.tr(),
                      dense: true,
                      onTap: _deleteAccount,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final UserData? user;

  const _ProfileAvatar({this.user});

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final cs = Theme.of(context).colorScheme;
    if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: cs.onPrimary, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            user!.photoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) =>
                _placeholder(size, Theme.of(ctx).colorScheme),
          ),
        ),
      );
    }

    if (user != null && user!.name.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.onPrimary.withValues(alpha: 0.22),
          border: Border.all(color: cs.onPrimary, width: 2.5),
        ),
        alignment: Alignment.center,
        child: Text(
          user!.name[0].toUpperCase(),
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return _placeholder(size, cs);
  }

  Widget _placeholder(double size, ColorScheme cs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.onPrimary.withValues(alpha: 0.2),
        border: Border.all(color: cs.onPrimary, width: 2.5),
      ),
      child: Icon(Icons.person_rounded, color: cs.onPrimary, size: 38),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dense;

  const _ProfileActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 14 : 16,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

