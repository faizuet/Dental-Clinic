import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../errors/friendly_error.dart';
import '../models/session_models.dart';
import '../security/device_id.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

enum AppRouteGate { splash, login, ready }

class SessionState {
  const SessionState({
    this.initialized = false,
    this.hasTokens = false,
    this.busy = false,
    this.error,
    this.user,
    this.clinic,
  });

  final bool initialized;
  final bool hasTokens;
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
    return AppRouteGate.ready;
  }

  SessionState copyWith({
    bool? initialized,
    bool? hasTokens,
    bool? busy,
    String? error,
    bool clearError = false,
    UserProfile? user,
    ClinicProfile? clinic,
  }) {
    return SessionState(
      initialized: initialized ?? this.initialized,
      hasTokens: hasTokens ?? this.hasTokens,
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
    required AppDatabase database,
    ApiClient? api,
  })  : _auth = auth,
        _tokens = tokens,
        _database = database,
        super(const SessionState()) {
    api?.onSessionInvalid = markUnauthenticated;
  }

  final AuthRepository _auth;
  final TokenStorage _tokens;
  final AppDatabase _database;

  Future<void> bootstrap() async {
    final snapshot = await _auth.loadCachedProfile();
    if (!await _tokens.hasTokens()) {
      state = SessionState(
        initialized: true,
        hasTokens: false,
        user: snapshot?.$1,
        clinic: snapshot?.$2,
      );
      return;
    }

    try {
      final live = await _auth.restoreSession();
      state = SessionState(
        initialized: true,
        hasTokens: true,
        user: live.$1,
        clinic: live.$2,
      );
    } on UnauthorizedException {
      await _tokens.clear();
      state = SessionState(
        initialized: true,
        hasTokens: false,
        user: snapshot?.$1,
        clinic: snapshot?.$2,
      );
    } catch (_) {
      final stillHasTokens = await _tokens.hasTokens();
      state = SessionState(
        initialized: true,
        hasTokens: stillHasTokens,
        user: snapshot?.$1,
        clinic: snapshot?.$2,
      );
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _auth.login(email: email, password: password);
      state = state.copyWith(
        initialized: true,
        busy: false,
        hasTokens: true,
        user: result.$1,
        clinic: result.$2,
      );
      return true;
    } catch (error) {
      state = state.copyWith(initialized: true, busy: false, error: friendlyError(error));
      return false;
    }
  }

  Future<void> applyProfile(UserProfile user, ClinicProfile clinic) async {
    await _database.saveSnapshot(user: user, clinic: clinic);
    state = state.copyWith(user: user, clinic: clinic);
  }

  void markUnauthenticated() {
    if (!state.hasTokens && state.initialized) {
      return;
    }
    state = SessionState(
      initialized: true,
      hasTokens: false,
      user: state.user,
      clinic: state.clinic,
    );
  }

  Future<void> logout({bool allDevices = false}) async {
    await _auth.logout(allDevices: allDevices);
    final snapshot = await _database.readSnapshot();
    state = SessionState(
      initialized: true,
      hasTokens: false,
      user: snapshot?.$1,
      clinic: snapshot?.$2,
    );
  }
}

final tokenStorageProvider = Provider((ref) => TokenStorage());
final deviceIdentityProvider = Provider((ref) => DeviceIdentity());
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
    database: ref.watch(databaseProvider),
    api: ref.watch(apiClientProvider),
  );
});

class SessionListenable extends ChangeNotifier {
  SessionListenable(this._ref) {
    _ref.listen(sessionProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}
