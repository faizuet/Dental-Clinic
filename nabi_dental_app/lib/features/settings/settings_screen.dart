import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import 'profile_avatar.dart';

final pendingCountProvider = FutureProvider<int>((ref) {
  return ref.watch(databaseProvider).pendingCount();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _message;
  bool _busy = false;
  bool _biometrics = false;
  bool _canBiometrics = false;
  SyncStatus? _sync;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final pin = ref.read(pinServiceProvider);
    final sync = await ref.read(financeRepositoryProvider).syncStatus();
    final canBio = await pin.canUseBiometrics();
    final bio = await pin.biometricsEnabled();
    if (mounted) {
      setState(() {
        _sync = sync;
        _canBiometrics = canBio;
        _biometrics = bio;
      });
    }
  }

  Future<void> _confirmLogout({required bool allDevices}) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: allDevices ? 'Sign out everywhere?' : 'Sign out?',
      message: allDevices
          ? 'Every signed-in device will return to the login screen. Records saved on this phone stay here.'
          : 'This phone will return to the sign-in screen. Records saved here stay on the phone.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (ok == true) {
      await ref.read(sessionProvider.notifier).logout(allDevices: allDevices);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Change password',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
      ],
    );
    if (confirmed != true) {
      current.dispose();
      next.dispose();
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (mounted) {
        showAppSnack(context, 'Password updated.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = friendlyError(error));
      }
    } finally {
      current.dispose();
      next.dispose();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retrySync() async {
    setState(() => _busy = true);
    await ref.read(financeRepositoryProvider).refresh();
    await _loadExtras();
    ref.invalidate(pendingCountProvider);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  String _syncSubtitle(int? pending) {
    if (pending != null && pending > 0) {
      return pending == 1 ? '1 change waiting to sync' : '$pending changes waiting to sync';
    }
    if ((_sync?.conflicts ?? 0) > 0) {
      return '${_sync!.conflicts} conflicts need a review';
    }
    return 'Keep this phone in sync with the clinic';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pending = ref.watch(pendingCountProvider);
    final pendingCount = pending.asData?.value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/modules'),
        title: const AppBarTitle('Settings'),
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: ListView(
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
            if (_message != null) ...[
              ErrorBanner(message: _message!),
              const SizedBox(height: 16),
            ],
            AppReveal(
              child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                onTap: () => appPush(context, '/settings/profile'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                  child: Row(
                    children: [
                      const SessionAvatar(size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.user?.fullName ?? 'Owner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              session.user?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'View profile and photo',
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.purple),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
            ),
            const SectionHeader('Clinic'),
            Card(
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.category_outlined,
                    title: 'Catalogs',
                    subtitle: 'Treatments and expense categories',
                    onTap: () => appPush(context, '/settings/catalogs'),
                  ),
                  const Divider(indent: 68),
                  _SettingsTile(
                    icon: Icons.sync_rounded,
                    title: 'Retry sync',
                    subtitle: _syncSubtitle(pendingCount),
                    onTap: _busy ? null : _retrySync,
                  ),
                  const Divider(indent: 68),
                  _SettingsTile(
                    icon: Icons.merge_type_rounded,
                    title: 'Conflict review',
                    subtitle: (_sync?.conflicts ?? 0) > 0
                        ? '${_sync!.conflicts} items need a choice'
                        : 'Choose local or server values when they differ',
                    onTap: () => appPush(context, '/settings/conflicts'),
                  ),
                ],
              ),
            ),
            const SectionHeader('Security'),
            Card(
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.pin_outlined,
                    title: 'Change PIN',
                    subtitle: 'This PIN stays on this device',
                    onTap: () => appPush(context, '/settings/pin'),
                  ),
                  if (_canBiometrics) ...[
                    const Divider(indent: 68),
                    SwitchListTile(
                      value: _biometrics,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      onChanged: (value) async {
                        await ref.read(pinServiceProvider).setBiometricsEnabled(value);
                        setState(() => _biometrics = value);
                      },
                      title: const Text('Unlock with biometrics', maxLines: 2),
                      subtitle: const Text('Use fingerprint or Face ID on this phone'),
                      secondary: const Icon(Icons.fingerprint_rounded),
                    ),
                  ],
                  const Divider(indent: 68),
                  _SettingsTile(
                    icon: Icons.lock_reset_rounded,
                    title: 'Change password',
                    subtitle: 'Updates the owner password on the server',
                    onTap: _busy ? null : _changePassword,
                  ),
                ],
              ),
            ),
            const SectionHeader('Account'),
            Card(
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out this device',
                    subtitle: 'Return to the sign-in screen',
                    iconColor: AppColors.danger,
                    titleColor: AppColors.danger,
                    onTap: () => _confirmLogout(allDevices: false),
                  ),
                  const Divider(indent: 68),
                  _SettingsTile(
                    icon: Icons.phonelink_erase_rounded,
                    title: 'Sign out all devices',
                    subtitle: 'Revoke access on every signed-in phone',
                    iconColor: AppColors.danger,
                    titleColor: AppColors.danger,
                    onTap: () => _confirmLogout(allDevices: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primary).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: titleColor == null ? null : TextStyle(color: titleColor, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
