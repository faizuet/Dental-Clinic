import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/pin_keypad.dart';

class PinChangeScreen extends ConsumerStatefulWidget {
  const PinChangeScreen({super.key});

  @override
  ConsumerState<PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends ConsumerState<PinChangeScreen> {
  int _length = 4;
  String _first = '';
  String _confirm = '';
  bool _confirming = false;
  String? _error;

  String get _current => _confirming ? _confirm : _first;

  Future<void> _addDigit(String digit) async {
    if (_current.length >= _length) {
      return;
    }
    setState(() {
      _error = null;
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
      if (_confirming && _confirm.isNotEmpty) {
        _confirm = _confirm.substring(0, _confirm.length - 1);
      } else if (!_confirming && _first.isNotEmpty) {
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
        _error = 'The PINs do not match. Try again.';
        _first = '';
        _confirm = '';
        _confirming = false;
      });
      return;
    }
    await ref.read(pinServiceProvider).setPin(_first);
    if (mounted) {
      showAppSnack(context, 'PIN updated on this device.');
      appPop(context, fallback: '/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const AppBarTitle('Change PIN'),
      ),
      body: PinScreenScaffold(
        header: Column(
          children: [
            Text(
              _confirming ? 'Confirm your $_length-digit PIN' : 'Choose a new $_length-digit PIN',
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
                    _error = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            PinDots(length: _length, filled: _current.length),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(message: _error!),
            ],
          ],
        ),
        keypad: PinKeypad(onDigit: _addDigit, onBackspace: _backspace),
      ),
    );
  }
}
