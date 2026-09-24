import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/pin_keypad.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  int _length = 4;
  String _first = '';
  String _confirm = '';
  bool _confirming = false;
  bool _enableBiometrics = false;
  bool _canUseBiometrics = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadBiometrics);
  }

  Future<void> _loadBiometrics() async {
    final canUse = await ref.read(pinServiceProvider).canUseBiometrics();
    if (mounted) {
      setState(() => _canUseBiometrics = canUse);
    }
  }

  String get _current => _confirming ? _confirm : _first;

  Future<void> _addDigit(String digit) async {
    if (_current.length >= _length) {
      return;
    }
    setState(() {
      _localError = null;
      if (_confirming) {
        _confirm += digit;
      } else {
        _first += digit;
      }
    });
    if ((_confirming ? _confirm : _first).length == _length) {
      await _advance();
    }
  }

  void _backspace() {
    setState(() {
      if (_confirming) {
        if (_confirm.isEmpty) {
          return;
        }
        _confirm = _confirm.substring(0, _confirm.length - 1);
      } else if (_first.isNotEmpty) {
        _first = _first.substring(0, _first.length - 1);
      }
    });
  }

  Future<void> _advance() async {
    if (!_confirming) {
      setState(() => _confirming = true);
      return;
    }
    if (_first != _confirm) {
      setState(() {
        _localError = 'The PINs do not match. Try again.';
        _first = '';
        _confirm = '';
        _confirming = false;
      });
      return;
    }
    await ref.read(sessionProvider.notifier).setupPin(_first, enableBiometrics: _enableBiometrics);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final error = _localError ?? session.error;

    return AppExitScope(
      child: Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Create a PIN'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: PinScreenScaffold(
        header: Column(
          children: [
            Text(
              _confirming ? 'Confirm your $_length-digit PIN' : 'Choose a $_length-digit PIN for this device',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'This PIN never leaves the phone.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            FittedBox(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 4, label: Text('4 digits')),
                  ButtonSegment(value: 6, label: Text('6 digits')),
                ],
                selected: {_length},
                onSelectionChanged: (value) {
                  setState(() {
                    _length = value.first;
                    _first = '';
                    _confirm = '';
                    _confirming = false;
                    _localError = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            PinDots(length: _length, filled: _current.length),
            if (error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: error),
            ],
            if (_canUseBiometrics)
              SwitchListTile(
                value: _enableBiometrics,
                onChanged: (value) => setState(() => _enableBiometrics = value),
                title: const Text('Unlock with biometrics', maxLines: 2),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
        keypad: PinKeypad(onDigit: _addDigit, onBackspace: _backspace),
      ),
      ),
    );
  }
}
