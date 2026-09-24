import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/profile/avatar_validation.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import 'profile_avatar.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _fullName;
  late final TextEditingController _clinicName;
  late final TextEditingController _currency;
  late final TextEditingController _timezone;
  late final TextEditingController _budget;
  String? _message;
  bool _busy = false;
  bool _dirty = false;
  bool _baselineReady = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _fullName = TextEditingController(text: session.user?.fullName ?? '');
    _clinicName = TextEditingController(text: session.clinic?.name ?? '');
    _currency = TextEditingController(text: session.clinic?.currency ?? 'PKR');
    _timezone = TextEditingController(text: session.clinic?.timezone ?? 'Asia/Karachi');
    _budget = TextEditingController(text: session.user?.defaultHomeBudget ?? '30000.00');
    for (final controller in [_fullName, _clinicName, _currency, _timezone, _budget]) {
      controller.addListener(_markDirty);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _baselineReady = true;
    });
  }

  @override
  void dispose() {
    for (final controller in [_fullName, _clinicName, _currency, _timezone, _budget]) {
      controller.removeListener(_markDirty);
      controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_baselineReady || _dirty) {
      return;
    }
    setState(() => _dirty = true);
  }

  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).updateSettings({
        'clinic_name': _clinicName.text.trim(),
        'currency': _currency.text.trim().toUpperCase(),
        'timezone': _timezone.text.trim(),
        'full_name': _fullName.text.trim(),
        'default_home_budget': moneyFromDouble(moneyToDouble(_budget.text)),
      });
      await ref.read(sessionProvider.notifier).applyProfile(result.$1, result.$2);
      if (mounted) {
        setState(() => _dirty = false);
        showAppSnack(context, 'Profile saved.');
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

  Future<void> _changePhoto() async {
    final user = ref.read(sessionProvider).user;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              if (user?.hasAvatar == true)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: const Text('Remove photo', style: TextStyle(color: AppColors.danger)),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'remove') {
      await _removePhoto();
      return;
    }
    await _pickPhoto(action == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 92);
    if (file == null || !mounted) {
      return;
    }
    final bytes = await file.readAsBytes();
    final filename = file.name.isEmpty ? 'photo.jpg' : file.name;
    final fileError = validateAvatarFile(filename: filename, byteLength: bytes.length);
    final imageError = fileError ?? await validateAvatarImage(Uint8List.fromList(bytes));
    if (!mounted) {
      return;
    }
    if (imageError != null) {
      setState(() => _message = imageError);
      return;
    }
    final confirmed = await _previewPhoto(Uint8List.fromList(bytes));
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).uploadAvatar(
            bytes: bytes,
            filename: filename,
          );
      await ref.read(sessionProvider.notifier).applyProfile(result.$1, result.$2);
      ref.invalidate(avatarBytesProvider);
      if (mounted) {
        showAppSnack(context, 'Profile photo updated.');
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

  Future<bool?> _previewPhoto(Uint8List bytes) {
    return showAppDialog<bool>(
      context: context,
      title: 'Use this photo?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.memory(
              bytes,
              width: 160,
              height: 160,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          const Text('This photo will appear on your profile and in Settings.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save photo')),
      ],
    );
  }

  Future<void> _removePhoto() async {
    final ok = await showAppDialog<bool>(
      context: context,
      title: 'Remove profile photo?',
      content: const Text('Your initials will be shown instead.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).deleteAvatar();
      await ref.read(sessionProvider.notifier).applyProfile(result.$1, result.$2);
      ref.invalidate(avatarBytesProvider);
      if (mounted) {
        showAppSnack(context, 'Profile photo removed.');
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = session.user;

    return AppDiscardScope(
      dirty: _dirty,
      fallback: '/settings',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallback: '/settings'),
          title: const AppBarTitle('Profile'),
        ),
        body: AppPageBody(
          padding: AppLayout.pagePadding(context, top: 8, bottom: 16),
          child: ListView(
            children: [
              if (_message != null) ...[
                ErrorBanner(message: _message!),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    children: [
                      SessionAvatar(
                        size: 104,
                        showEdit: true,
                        loading: _busy,
                        onTap: _busy ? null : _changePhoto,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        user?.fullName ?? 'Owner',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _busy ? null : _changePhoto,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(user?.hasAvatar == true ? 'Change photo' : 'Add photo'),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Account'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _fullName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Your name'),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Email',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          user?.email ?? '—',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Email cannot be changed here.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Clinic'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _clinicName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Clinic name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _currency,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Currency'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _timezone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Timezone'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _budget,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: 'Default home budget'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _saveProfile,
                child: Text(_busy ? 'Saving…' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
