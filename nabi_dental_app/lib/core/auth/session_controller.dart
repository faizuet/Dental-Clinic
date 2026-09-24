import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../database/app_database.dart';
import '../errors/friendly_error.dart';
import '../models/session_models.dart';
import '../security/device_id.dart';
import '../security/pin_service.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

enum AppRouteGate { splash, login, pinSetup, unlock, ready }

class SessionState {
  const SessionState({
    this.initialized = false,
    this.unlocked = false,
    this.hasTokens = false,
    this.hasPin = false,
    this.busy = false,
    this.error,
    this.user,
    this.clinic,
  });

  final bool initialized;
  final bool unlocked;
  final bool hasTokens;
  final bool hasPin;
  final bool busy;
  final String? error;
  final UserProfile? user;
  final ClinicProfile? clinic;

  AppRouteGate get gate {
    if (!initialized) {
      return AppRouteGate.splash;
    }
    if (!hasTokens) {
      return AppRouteGate.login;
    }
    if (!hasPin) {
      return AppRouteGate.pinSetup;
    }
    if (!unlocked) {
      return AppRouteGate.unlock;
    }
    return AppRouteGate.ready;
  }

  SessionState copyWith({
    bool? initialized,
    bool? unlocked,
    bool? hasTokens,
    bool? hasPin,
    bool? busy,
    String? error,
    bool clearError = false,
    UserProfile? user,
    ClinicProfile? clinic,
  }) {
    return SessionState(
      initialized: initialized ?? this.initialized,
      unlocked: unlocked ?? this.unlocked,
      hasTokens: hasTokens ?? this.hasTokens,
      hasPin: hasPin ?? this.hasPin,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      user: user ?? this.user,
      clinic: clinic ?? this.clinic,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required AuthRepository auth,
    required TokenStorage tokens,
    required PinService pin,
    required AppDatabase database,
  })  : _auth = auth,
        _tokens = tokens,
        _pin = pin,
        _database = database,
        super(const SessionState());

  final AuthRepository _auth;
  final TokenStorage _tokens;
  final PinService _pin;
  final AppDatabase _database;

  Future<void> bootstrap() async {
    final hasTokens = await _tokens.hasTokens();
    final hasPin = await _pin.hasPin();
    final snapshot = await _auth.loadCachedProfile();
    state = SessionState(
      initialized: true,
      hasTokens: hasTokens,
      hasPin: hasPin,
      unlocked: false,
      user: snapshot?.$1,
      clinic: snapshot?.$2,
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _auth.login(email: email, password: password);
      final hasPin = await _pin.hasPin();
      state = state.copyWith(
        initialized: true,
        busy: false,
        hasTokens: true,
        hasPin: hasPin,
        unlocked: hasPin,
        user: result.$1,
        clinic: result.$2,
      );
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: friendlyError(error));
      return false;
    }
  }

  Future<bool> setupPin(String pin, {required bool enableBiometrics}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _pin.setPin(pin);
      await _pin.setBiometricsEnabled(enableBiometrics);
      state = state.copyWith(busy: false, hasPin: true, unlocked: true);
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: friendlyError(error));
      return false;
    }
  }

  Future<void> applyProfile(UserProfile user, ClinicProfile clinic) async {
    await _database.saveSnapshot(user: user, clinic: clinic);
    state = state.copyWith(user: user, clinic: clinic);
  }

  Future<bool> unlockWithPin(String pin) async {
    if (await _pin.isLockedOut()) {
      state = state.copyWith(error: 'Too many attempts. Use secure logout and sign in again.');
      return false;
    }
    final ok = await _pin.verifyPin(pin);
    if (ok) {
      state = state.copyWith(unlocked: true, clearError: true);
      return true;
    }
    state = state.copyWith(error: 'That PIN is incorrect.');
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    final ok = await _pin.authenticateBiometrics();
    if (ok) {
      state = state.copyWith(unlocked: true, clearError: true);
    }
    return ok;
  }

  Future<void> logout({bool allDevices = false, bool clearPin = true}) async {
    await _auth.logout(allDevices: allDevices);
    if (clearPin) {
      await _pin.clear();
    }
    final snapshot = await _database.readSnapshot();
    state = SessionState(
      initialized: true,
      hasTokens: false,
      hasPin: false,
      unlocked: false,
      user: snapshot?.$1,
      clinic: snapshot?.$2,
    );
  }
}

final tokenStorageProvider = Provider((ref) => TokenStorage());
final deviceIdentityProvider = Provider((ref) => DeviceIdentity());
final pinServiceProvider = Provider((ref) => PinService());
final databaseProvider = Provider((ref) => AppDatabase());

final apiClientProvider = Provider((ref) {
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    deviceIdentity: ref.watch(deviceIdentityProvider),
  );
});

final authRepositoryProvider = Provider((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStorageProvider),
    device: ref.watch(deviceIdentityProvider),
    database: ref.watch(databaseProvider),
  );
});

final sessionProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(
    auth: ref.watch(authRepositoryProvider),
    tokens: ref.watch(tokenStorageProvider),
    pin: ref.watch(pinServiceProvider),
    database: ref.watch(databaseProvider),
  );
});

class SessionListenable extends ChangeNotifier {
  SessionListenable(this._ref) {
    _ref.listen(sessionProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}
