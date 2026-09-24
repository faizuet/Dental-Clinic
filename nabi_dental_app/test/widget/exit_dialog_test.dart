import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/security/pin_service.dart';
import 'package:nabi_dental_app/features/module_selection/module_selection_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Pin extends Mock implements PinService {}

class _Db extends Mock implements AppDatabase {}

void main() {
  testWidgets('root back asks before exiting', (tester) async {
    final controller = SessionController(
      auth: _Auth(),
      tokens: _Tokens(),
      pin: _Pin(),
      database: _Db(),
    )..state = const SessionState(
        initialized: true,
        hasTokens: true,
        hasPin: true,
        unlocked: true,
        user: UserProfile(
          id: '1',
          fullName: 'Dr Owner',
          email: 'owner@example.com',
          role: 'owner',
          defaultHomeBudget: '50000.00',
        ),
        clinic: ClinicProfile(
          id: '1',
          name: 'Nabi Dental',
          currency: 'PKR',
          timezone: 'Asia/Karachi',
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: ModuleSelectionScreen()),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Do you want to exit the app?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clinic Finance'), findsOneWidget);
  });
}
