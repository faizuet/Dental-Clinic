import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/passwords.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';

Future<bool> promptChangePassword(
  BuildContext context,
  WidgetRef ref, {
  bool requiredChange = false,
}) async {
  if (!context.mounted) {
    return false;
  }
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: !requiredChange,
    useRootNavigator: true,
    builder: (dialogContext) => _ChangePasswordDialog(requiredChange: requiredChange),
  );
  if (changed != true) {
    return false;
  }
  if (!context.mounted) {
    return true;
  }
  try {
    await ref.read(sessionProvider.notifier).logout();
  } catch (_) {}
  if (context.mounted) {
    showAppSnack(context, 'Password updated. Sign in with the new password.');
  }
  return true;
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog({required this.requiredChange});

  final bool requiredChange;

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _obscure = true;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _formKey.currentState?.validate() != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = size.width < 360 ? 16.0 : 24.0;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(AppRadii.md)),
            child: const Icon(Icons.lock_reset_rounded, color: AppColors.purple),
          ),
          const SizedBox(height: 14),
          Text(
            widget.requiredChange ? 'Choose a clinic password' : 'Change password',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SizedBox(
        width: AppLayout.dialogWidth(context),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.requiredChange) ...[
                  Text(
                    'The example password is only for first setup. Choose a password only you know, at least 10 characters.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _current,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your current password.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _next,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 10 characters',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter a new password.';
                    }
                    if (value.length < 10) {
                      return 'Use at least 10 characters.';
                    }
                    if (value == _current.text) {
                      return 'Choose a different password.';
                    }
                    if (isExampleOwnerPassword(value)) {
                      return 'Do not reuse the example password.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: _busy ? null : () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                  validator: (value) {
                    if (value != _next.text) {
                      return 'The new passwords do not match.';
                    }
                    return null;
                  },
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!widget.requiredChange)
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Update'),
        ),
      ],
    );
  }
}
