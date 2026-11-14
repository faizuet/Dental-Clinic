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
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/page_kit.dart';
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
    final conflicts = _sync?.conflicts ?? 0;

    final backup = _section(
      title: 'Backup & Restore',
      subtitle: 'Keep a copy of clinic data on a USB drive',
      icon: Icons.backup_rounded,
      color: AppColors.success,
      soft: AppColors.mintSoft,
      tiles: [
        _SettingsTile(
          icon: Icons.save_alt_rounded,
          title: 'Save clinic backup',
          subtitle: _backup.subtitle,
          iconColor: AppColors.success,
          badge: _backup.isOverdue ? const StatusPill(label: 'Due', color: AppColors.orange, soft: AppColors.warningSoft) : null,
          onTap: _busy ? null : _exportBackup,
        ),
        _SettingsTile(
          icon: Icons.settings_backup_restore_rounded,
          title: 'Restore from backup',
          subtitle: 'Replace this computer with a saved zip',
          iconColor: AppColors.orange,
          onTap: _busy ? null : _restoreBackup,
        ),
      ],
    );
    final clinic = _section(
      title: 'Clinic Data',
      subtitle: 'Catalogs and sync for this computer',
      icon: Icons.local_hospital_rounded,
      color: AppColors.primary,
      soft: AppColors.primarySoft,
      tiles: [
        _SettingsTile(
          icon: Icons.category_rounded,
          title: 'Catalogs',
          subtitle: 'Treatments and expense categories',
          onTap: () => appPush(context, '/settings/catalogs'),
        ),
        _SettingsTile(
          icon: Icons.sync_rounded,
          title: 'Retry sync',
          subtitle: _syncSubtitle(pendingCount),
          iconColor: AppColors.aqua,
          badge: (pendingCount ?? 0) > 0 ? StatusPill(label: '$pendingCount', color: AppColors.aqua, soft: AppColors.aquaSoft) : null,
          onTap: _busy ? null : _retrySync,
        ),
        _SettingsTile(
          icon: Icons.merge_type_rounded,
          title: 'Conflict review',
          subtitle: conflicts > 0 ? '$conflicts items need a choice' : 'Choose local or server values when they differ',
          iconColor: AppColors.violet,
          badge: conflicts > 0 ? StatusPill(label: '$conflicts', color: AppColors.danger, soft: AppColors.dangerSoft) : null,
          onTap: () => appPush(context, '/settings/conflicts'),
        ),
      ],
    );
    final security = _section(
      title: 'Security',
      subtitle: 'Protect the owner account',
      icon: Icons.shield_rounded,
      color: AppColors.violet,
      soft: AppColors.violetSoft,
      tiles: [
        _SettingsTile(
          icon: Icons.lock_reset_rounded,
          title: 'Change password',
          subtitle: 'Updates the owner password on the server',
          iconColor: AppColors.violet,
          onTap: _busy ? null : _changePassword,
        ),
      ],
    );
    final account = _section(
      title: 'Account',
      subtitle: 'Sign out of the app',
      icon: Icons.manage_accounts_rounded,
      color: AppColors.danger,
      soft: AppColors.dangerSoft,
      tiles: [
        _SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign out this device',
          subtitle: 'Return to the sign-in screen',
          iconColor: AppColors.danger,
          titleColor: AppColors.danger,
          onTap: () => _confirmLogout(allDevices: false),
        ),
        _SettingsTile(
          icon: Icons.phonelink_erase_rounded,
          title: 'Sign out all devices',
          subtitle: 'Revoke access on every signed-in device',
          iconColor: AppColors.danger,
          titleColor: AppColors.danger,
          onTap: () => _confirmLogout(allDevices: true),
        ),
      ],
    );

    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Settings',
        isRoot: true,
        fallback: '/clinic',
      ),
      body: PageScaffoldBody(
        children: [
          const PageHeader(
            icon: Icons.settings_rounded,
            title: 'Settings',
            subtitle: 'Manage your profile, backups, sync, and security',
          ),
          const SizedBox(height: 20),
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
          ],
          if (_message != null) ...[
            ErrorBanner(message: _message!),
            const SizedBox(height: 16),
          ],
          AppReveal(child: _profileCard(session.user?.fullName ?? 'Owner', session.user?.email ?? '')),
          const SizedBox(height: 20),
          AppSplit(breakpoint: 900, primaryFlex: 1, secondaryFlex: 1, primary: backup, secondary: clinic),
          const SizedBox(height: 20),
          AppSplit(breakpoint: 900, primaryFlex: 1, secondaryFlex: 1, primary: security, secondary: account),
        ],
      ),
    );
  }

  Widget _profileCard(String name, String email) {
    final theme = Theme.of(context);
    return TablePanel(
      child: InkWell(
        onTap: () => appPush(context, '/settings/profile'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          child: Row(
            children: [
              const SessionAvatar(size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const StatusPill(label: 'Owner', color: AppColors.primary, soft: AppColors.primarySoft),
                      ],
                    ),
                    const SizedBox(height: 4),
                    IconText(icon: Icons.mail_outline_rounded, text: email, muted: true),
                    const SizedBox(height: 6),
                    Text(
                      'View profile and photo',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color soft,
    required List<Widget> tiles,
  }) {
    return TablePanel(
      header: PanelTitle(title: title, subtitle: subtitle, icon: icon, color: color, soft: soft),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            tiles[i],
          ],
        ],
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
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      enabled: onTap != null,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[badge!, const SizedBox(width: 8)],
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
      onTap: onTap,
    );
  }
}
