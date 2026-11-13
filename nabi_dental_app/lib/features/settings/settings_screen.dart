import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/backup/backup_status.dart';
import '../../core/export/file_saver.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import 'change_password_dialog.dart';
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
  SyncStatus? _sync;
  BackupStatus _backup = const BackupStatus();

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final repo = ref.read(financeRepositoryProvider);
    final sync = await repo.syncStatus();
    final backup = await repo.backupStatus();
    if (mounted) {
      setState(() {
        _sync = sync;
        _backup = backup;
      });
    }
  }

  Future<void> _confirmLogout({required bool allDevices}) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: allDevices ? 'Sign out everywhere?' : 'Sign out?',
      message: allDevices
          ? 'Every signed-in device will return to the login screen. Records saved on this computer stay here.'
          : 'This computer will return to the sign-in screen. Records saved here stay on this device.',
      confirmLabel: 'Sign out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (ok == true) {
      await ref.read(sessionProvider.notifier).logout(allDevices: allDevices);
    }
  }

  Future<void> _changePassword() async {
    await promptChangePassword(context, ref);
  }

  Future<void> _exportBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await ref.read(financeRepositoryProvider).exportBackup();
      if (file.bytes.isEmpty) {
        throw Exception('The backup file was empty. Try again.');
      }
      final saved = await saveBytesWithPicker(
        bytes: file.bytes,
        filename: file.filename,
        mime: file.mime,
        label: 'Clinic backup',
        extensions: const ['zip'],
      );
      if (saved == null) {
        return;
      }
      await ref.read(financeRepositoryProvider).markBackupSaved();
      await _loadExtras();
      if (mounted) {
        showAppSnack(context, 'Backup saved. Keep a copy on a USB drive.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreBackup() async {
    final pending = await ref.read(financeRepositoryProvider).syncStatus();
    if (pending.pending > 0) {
      if (!mounted) {
        return;
      }
      await showAppConfirmDialog(
        context: context,
        title: 'Sync waiting changes first',
        message: pending.pending == 1
            ? '1 change is waiting to sync. Retry sync before replacing clinic data, or those records will be lost.'
            : '${pending.pending} changes are waiting to sync. Retry sync before replacing clinic data, or those records will be lost.',
        confirmLabel: 'OK',
        icon: Icons.sync_problem_rounded,
      );
      return;
    }
    const group = XTypeGroup(label: 'Clinic backup', extensions: ['zip']);
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null) {
      return;
    }
    final path = picked.path;
    if (path.isEmpty) {
      if (mounted) {
        setState(() => _message = 'Choose a backup zip from this computer.');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final replaced = await showAppDeleteDialog(
      context: context,
      title: 'Replace clinic data?',
      message:
          'This replaces all patients, treatment records, expenses, and X-rays on this computer with the backup. Current records are not kept unless you already saved a newer backup.',
      confirmLabel: 'Replace data',
      onConfirm: () => ref.read(financeRepositoryProvider).restoreBackup(
            path: path,
            filename: picked.name.isNotEmpty ? picked.name : 'clinic-backup.zip',
          ),
    );
    if (replaced != true) {
      return;
    }
    await ref.read(financeRepositoryProvider).markBackupSaved();
    ref.read(financeEpochProvider.notifier).state++;
    await _loadExtras();
    if (mounted) {
      showAppSnack(context, 'Clinic data restored from backup.');
    }
  }

  Future<void> _retrySync() async {
    setState(() => _busy = true);
    await ref.read(financeRepositoryProvider).refresh(force: true);
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
    return 'Keep this computer in sync with the clinic';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pending = ref.watch(pendingCountProvider);
    final pendingCount = pending.asData?.value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Settings',
        isRoot: true,
        fallback: '/clinic',
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: ListView(
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
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
            const SectionHeader('Backup'),
            Card(
              child: Column(
                children: [
                  _SettingsTile(
                    icon: Icons.save_alt_rounded,
                    title: 'Save clinic backup',
                    subtitle: _backup.subtitle,
                    onTap: _busy ? null : _exportBackup,
                  ),
                  const Divider(indent: 68),
                  _SettingsTile(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Restore from backup',
                    subtitle: 'Replace this computer with a saved zip',
                    onTap: _busy ? null : _restoreBackup,
                  ),
                ],
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
              child: _SettingsTile(
                icon: Icons.lock_reset_rounded,
                title: 'Change password',
                subtitle: 'Updates the owner password on the server',
                onTap: _busy ? null : _changePassword,
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
                    subtitle: 'Revoke access on every signed-in device',
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
