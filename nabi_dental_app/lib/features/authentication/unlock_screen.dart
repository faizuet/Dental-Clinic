import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/brand_header.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/pin_keypad.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  String _pin = '';
  int _length = 4;
  bool _showBiometric = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepare);
  }

  Future<void> _prepare() async {
    final pin = ref.read(pinServiceProvider);
    final length = await pin.pinLength();
    final canBio = await pin.canUseBiometrics() && await pin.biometricsEnabled();
    if (mounted) {
      setState(() {
        _length = length;
        _showBiometric = canBio;
      });
    }
    if (canBio) {
      await ref.read(sessionProvider.notifier).unlockWithBiometrics();
    }
  }

  Future<void> _addDigit(String digit) async {
    if (_pin.length >= _length) {
      return;
    }
    final next = _pin + digit;
    setState(() => _pin = next);
    if (next.length == _length) {
      final ok = await ref.read(sessionProvider.notifier).unlockWithPin(next);
      if (!ok && mounted) {
        setState(() => _pin = '');
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) {
      return;
    }
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return AppExitScope(
      child: Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.purpleSoft, AppColors.background],
          ),
        ),
        child: PinScreenScaffold(
          header: Column(
            children: [
              BrandHeader(
                compact: true,
                subtitle: session.user == null ? 'Enter your device PIN' : 'Welcome back, ${session.user!.fullName}',
              ),
              const SizedBox(height: 24),
              PinDots(length: _length, filled: _pin.length),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _length = _length == 4 ? 6 : 4;
                  _pin = '';
                }),
                child: Text(_length == 4 ? 'Using a 6-digit PIN?' : 'Using a 4-digit PIN?'),
              ),
              if (session.error != null) ...[
                ErrorBanner(message: session.error!),
                const SizedBox(height: 12),
              ],
            ],
          ),
          keypad: PinKeypad(
            onDigit: _addDigit,
            onBackspace: _backspace,
            onBiometric: _showBiometric
                ? () => ref.read(sessionProvider.notifier).unlockWithBiometrics()
                : null,
          ),
          footer: TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            child: const Text('Sign out and use password', style: TextStyle(color: AppColors.muted)),
          ),
        ),
      ),
      ),
    );
  }
}
