import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/app/theme/app_theme.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/finance/finance_repository.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/utils/money.dart';
import 'package:nabi_dental_app/core/utils/period.dart';
import 'package:nabi_dental_app/features/clinic_dashboard/reports_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

class _Finance extends Mock implements FinanceRepository {}

MoneyEntry _entry({required String id, required String name, required String date, required String amount}) {
  return MoneyEntry(id: id, catalogId: id, catalogName: name, date: date, amount: amount);
}

List<NamedAmount> _breakdown(List<MoneyEntry> entries) {
  final totals = <String, double>{};
  for (final entry in entries) {
    totals[entry.catalogName] = (totals[entry.catalogName] ?? 0) + moneyToDouble(entry.amount);
  }
  final items = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
    ..sort((a, b) => moneyToDouble(b.amount).compareTo(moneyToDouble(a.amount)));
  return items;
}

List<NamedAmount> _timeline(List<MoneyEntry> entries) {
  final totals = <String, double>{};
  for (final entry in entries) {
    totals[entry.date] = (totals[entry.date] ?? 0) + moneyToDouble(entry.amount);
  }
  final items = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return items;
}

SessionController _session() {
  return SessionController(auth: _Auth(), tokens: _Tokens(), database: _Db())
    ..state = const SessionState(
      initialized: true,
      hasTokens: true,
      user: UserProfile(
        id: '1',
        fullName: 'Dr Owner',
        email: 'nabidentalclinic@gmail.com',
        role: 'owner',
        defaultHomeBudget: '50000.00',
      ),
      clinic: ClinicProfile(id: '1', name: 'Nabi Dental', currency: 'PKR', timezone: 'Asia/Karachi'),
    );
}

void _stubGrouping(_Finance finance) {
  when(() => finance.breakdown(any())).thenAnswer((invocation) async {
    return _breakdown(invocation.positionalArguments.first as List<MoneyEntry>);
  });
  when(() => finance.timeline(any())).thenAnswer((invocation) async {
    return _timeline(invocation.positionalArguments.first as List<MoneyEntry>);
  });
  when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);
}

Future<void> _pump(WidgetTester tester, Widget screen, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _session()),
        financeRepositoryProvider.overrideWithValue(_finance),
      ],
      child: MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: GoRouter(
          initialLocation: '/reports',
          routes: [
            GoRoute(path: '/clinic', builder: (_, __) => const SizedBox()),
            GoRoute(path: '/home', builder: (_, __) => const SizedBox()),
            GoRoute(path: '/reports', builder: (_, __) => screen),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

late _Finance _finance;

void main() {
  setUpAll(() {
    registerFallbackValue(false);
    registerFallbackValue('');
    registerFallbackValue(DateRange.forPeriod(FinancePeriod.monthly));
    registerFallbackValue(<MoneyEntry>[]);
  });

  setUp(() => _finance = _Finance());

  testWidgets('clinic reports keep the same totals in a wide layout', (tester) async {
    final income = [
      _entry(id: '1', name: 'Dental Gems', date: '2026-11-12', amount: '4000.00'),
      _entry(id: '2', name: 'Check Up / Consultation', date: '2026-11-14', amount: '3500.00'),
      _entry(id: '3', name: 'Porcelain Bridge', date: '2026-11-14', amount: '3000.00'),
      _entry(id: '4', name: 'Permanent Filling', date: '2026-11-12', amount: '600.00'),
      _entry(id: '5', name: 'Temporary Filling', date: '2026-11-12', amount: '500.00'),
    ];
    final expenses = [
      _entry(id: '6', name: 'Rent', date: '2026-11-14', amount: '5000.00'),
      _entry(id: '7', name: 'Materials', date: '2026-11-14', amount: '2000.00'),
    ];
    final labs = [
      _entry(id: '8', name: 'Bracese', date: '2026-11-14', amount: '1000.00'),
    ];
    when(() => _finance.incomeHistory(range: any(named: 'range'))).thenAnswer((_) async => income);
    when(() => _finance.clinicExpenseHistory(range: any(named: 'range'))).thenAnswer((_) async => expenses);
    when(() => _finance.labChargeHistory(range: any(named: 'range'))).thenAnswer((_) async => labs);
    _stubGrouping(_finance);

    await _pump(tester, const ClinicReportsScreen(), size: const Size(1400, 1500));

    expect(find.text('Dental Gems'), findsOneWidget);
    expect(find.text('Check Up / Consultation'), findsOneWidget);
    expect(find.text('Porcelain Bridge'), findsOneWidget);
    expect(find.text('Permanent Filling'), findsOneWidget);
    expect(find.text('Temporary Filling'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Materials'), findsOneWidget);
    expect(find.text('Bracese'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('26%'), findsOneWidget);
    expect(find.text('5.2%'), findsOneWidget);
    expect(find.text('4.3%'), findsOneWidget);
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('29%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('PKR 11,600.00'), findsWidgets);
    expect(find.text('PKR 7,000.00'), findsWidgets);
    expect(find.text('PKR 1,000.00'), findsWidgets);
    expect(find.text('PKR 3,600.00'), findsOneWidget);
    expect(find.text('12/11/26'), findsOneWidget);
    expect(find.text('14/11/26'), findsNWidgets(2));
    expect(find.text('PKR 5,100.00'), findsOneWidget);
    expect(find.text('PKR 6,500.00'), findsOneWidget);
    expect(find.text('PKR 18,600.00'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clinic reports stay readable in a narrow window', (tester) async {
    when(() => _finance.incomeHistory(range: any(named: 'range'))).thenAnswer(
      (_) async => [_entry(id: '1', name: 'Dental Gems', date: '2026-11-12', amount: '4000.00')],
    );
    when(() => _finance.clinicExpenseHistory(range: any(named: 'range'))).thenAnswer(
      (_) async => [
        _entry(id: '2', name: 'Rent', date: '2026-11-14', amount: '5000.00'),
        _entry(id: '3', name: 'Materials', date: '2026-11-14', amount: '2000.00'),
      ],
    );
    when(() => _finance.labChargeHistory(range: any(named: 'range'))).thenAnswer(
      (_) async => [
        _entry(id: '4', name: 'Bracese', date: '2026-11-14', amount: '600.00'),
        _entry(id: '5', name: 'Crown Lab', date: '2026-11-14', amount: '400.00'),
      ],
    );
    _stubGrouping(_finance);

    await _pump(tester, const ClinicReportsScreen(), size: const Size(720, 1600));

    expect(find.text('Materials'), findsOneWidget);
    expect(find.text('Crown Lab'), findsOneWidget);
    expect(find.text('Loss'), findsOneWidget);
    expect(find.text('PKR -4,000.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home reports keep spending, budget, and daily totals', (tester) async {
    when(() => _finance.homeExpenseHistory(range: any(named: 'range'))).thenAnswer(
      (_) async => [
        _entry(id: '1', name: 'Groceries', date: '2026-11-10', amount: '3000.00'),
        _entry(id: '2', name: 'Utilities', date: '2026-11-12', amount: '1000.00'),
      ],
    );
    when(() => _finance.homeTotals(any(), defaultBudget: any(named: 'defaultBudget'))).thenAnswer(
      (invocation) async => HomeTotals(
        spent: '4000.00',
        budget: '50000.00',
        remaining: '46000.00',
        percentageUsed: '8',
        budgetSource: 'default',
        range: invocation.positionalArguments.first as DateRange,
      ),
    );
    _stubGrouping(_finance);

    await _pump(tester, const HomeReportsScreen(), size: const Size(1400, 1100));

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Utilities'), findsOneWidget);
    expect(find.text('PKR 4,000.00'), findsWidgets);
    expect(find.text('PKR 50,000.00'), findsOneWidget);
    expect(find.text('PKR 46,000.00'), findsOneWidget);
    expect(find.text('10/11/26'), findsOneWidget);
    expect(find.text('12/11/26'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
