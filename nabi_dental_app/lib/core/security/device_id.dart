import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _idKey = 'device_id';
  final FlutterSecureStorage _storage;

  Future<String> id() async {
    final existing = await _storage.read(key: _idKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = const Uuid().v4();
    await _storage.write(key: _idKey, value: created);
    return created;
  }

  Future<String> name() async {
    if (kIsWeb) {
      return 'Web browser';
    }
    return defaultTargetPlatform.name;
  }
}
