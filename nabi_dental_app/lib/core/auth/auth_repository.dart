import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../models/session_models.dart';
import '../security/device_id.dart';
import 'token_storage.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient api,
    required TokenStorage tokens,
    required DeviceIdentity device,
    required AppDatabase database,
  })  : _api = api,
        _tokens = tokens,
        _device = device,
        _database = database;

  final ApiClient _api;
  final TokenStorage _tokens;
  final DeviceIdentity _device;
  final AppDatabase _database;

  Future<(UserProfile, ClinicProfile)> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      skipAuth: true,
      data: {
        'email': email.trim(),
        'password': password,
        'device_id': await _device.id(),
        'device_name': await _device.name(),
      },
    );
    final body = response.data ?? {};
    await _tokens.save(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
    final user = UserProfile.fromJson(body['user'] as Map<String, dynamic>);
    final clinic = ClinicProfile.fromJson(body['clinic'] as Map<String, dynamic>);
    await _database.saveSnapshot(user: user, clinic: clinic);
    try {
      await _api.post('/api/v1/sync/bootstrap');
    } catch (_) {
      // Cached profile is enough for first unlock; finance sync comes in later phases.
    }
    return (user, clinic);
  }

  Future<void> logout({required bool allDevices}) async {
    final refresh = await _tokens.readRefreshToken();
    try {
      if (allDevices) {
        await _api.post('/api/v1/auth/logout-all');
      } else if (refresh != null) {
        await _api.post('/api/v1/auth/logout', data: {'refresh_token': refresh}, skipAuth: true);
      }
    } catch (_) {
      // Local logout still proceeds.
    }
    await _tokens.clear();
  }

  Future<(UserProfile, ClinicProfile)?> loadCachedProfile() {
    return _database.readSnapshot();
  }

  Future<(UserProfile, ClinicProfile)> updateSettings(Map<String, dynamic> body) async {
    final response = await _api.patch('/api/v1/settings', data: body);
    return _snapshotFromSettings(Map<String, dynamic>.from((response.data as Map?) ?? {}));
  }

  Future<(UserProfile, ClinicProfile)> uploadAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final response = await _api.postMultipart(
      '/api/v1/settings/avatar',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return _snapshotFromSettings(Map<String, dynamic>.from((response.data as Map?) ?? {}));
  }

  Future<(UserProfile, ClinicProfile)> deleteAvatar() async {
    final response = await _api.delete('/api/v1/settings/avatar');
    return _snapshotFromSettings(Map<String, dynamic>.from((response.data as Map?) ?? {}));
  }

  Future<Uint8List?> downloadAvatar() async {
    try {
      final response = await _api.getBytes('/api/v1/settings/avatar');
      final data = response.data;
      if (data == null || data.isEmpty) {
        return null;
      }
      return Uint8List.fromList(data);
    } on AppException {
      return null;
    }
  }

  Future<(UserProfile, ClinicProfile)> _snapshotFromSettings(Map<String, dynamic> data) async {
    final snapshot = await _database.readSnapshot();
    final user = UserProfile(
      id: snapshot?.$1.id ?? data['clinic_id'].toString(),
      fullName: data['full_name'].toString(),
      email: data['email'].toString(),
      role: snapshot?.$1.role ?? 'owner',
      defaultHomeBudget: data['default_home_budget'].toString(),
      hasAvatar: data['has_avatar'] == true,
    );
    final clinic = ClinicProfile(
      id: data['clinic_id'].toString(),
      name: data['clinic_name'].toString(),
      currency: data['currency'].toString(),
      timezone: data['timezone'].toString(),
    );
    await _database.saveSnapshot(user: user, clinic: clinic);
    return (user, clinic);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _api.post(
      '/api/v1/auth/change-password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }
}
