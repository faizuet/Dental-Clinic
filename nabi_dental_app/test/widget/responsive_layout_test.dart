import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/app/theme/app_theme.dart';
import 'package:nabi_dental_app/core/widgets/summary_card.dart';

void main() {
  testWidgets('cards and totals stay inside a compact phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SummaryCard(
                label: 'Clinic expenses',
                value: 'PKR 1,234,567.89',
                icon: Icons.trending_down_rounded,
              ),
              ActionCard(
                title: 'Income history',
                subtitle: 'Search, edit, or delete treatment income on this device',
                icon: Icons.history_rounded,
                onTap: () {},
              ),
              const TotalBar(label: 'Total', value: 'PKR 9,999,999.00'),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Clinic expenses'), findsOneWidget);
    expect(find.text('Income history'), findsOneWidget);
  });
}
