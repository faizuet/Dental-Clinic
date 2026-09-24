import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class PinService {
  PinService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';
  static const _lengthKey = 'pin_length';
  static const _bioKey = 'biometrics_enabled';
  static const _failKey = 'pin_fail_count';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _hashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<int> pinLength() async {
    return int.tryParse(await _storage.read(key: _lengthKey) ?? '4') ?? 4;
  }

  Future<void> setPin(String pin) async {
    if (pin.length != 4 && pin.length != 6) {
      throw ArgumentError('PIN must be 4 or 6 digits.');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain digits only.');
    }
    final salt = _randomSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: _hash(pin, salt));
    await _storage.write(key: _lengthKey, value: '${pin.length}');
    await _storage.write(key: _failKey, value: '0');
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final expected = await _storage.read(key: _hashKey);
    if (salt == null || expected == null) {
      return false;
    }
    final matches = _hash(pin, salt) == expected;
    if (matches) {
      await _storage.write(key: _failKey, value: '0');
      return true;
    }
    final fails = int.tryParse(await _storage.read(key: _failKey) ?? '0') ?? 0;
    await _storage.write(key: _failKey, value: '${fails + 1}');
    return false;
  }

  Future<int> failCount() async {
    return int.tryParse(await _storage.read(key: _failKey) ?? '0') ?? 0;
  }

  Future<bool> isLockedOut() async {
    return (await failCount()) >= 5;
  }

  Future<void> setBiometricsEnabled(bool enabled) {
    return _storage.write(key: _bioKey, value: enabled ? '1' : '0');
  }

  Future<bool> biometricsEnabled() async {
    return (await _storage.read(key: _bioKey)) == '1';
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometrics() async {
    if (!await biometricsEnabled()) {
      return false;
    }
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Nabi Dental Clinic',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _lengthKey);
    await _storage.delete(key: _bioKey);
    await _storage.delete(key: _failKey);
  }

  String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
