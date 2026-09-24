import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/app/theme/app_theme.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/security/pin_service.dart';
import 'package:nabi_dental_app/features/settings/profile_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Pin extends Mock implements PinService {}

class _Db extends Mock implements AppDatabase {}

void main() {
  testWidgets('profile shows a default avatar and real owner fields', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dr Owner'), findsWidgets);
    expect(find.text('owner@example.com'), findsWidgets);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Your name'), findsOneWidget);
  });
}
