import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session_controller.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/utils/money.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/status_banner.dart';

class HomeBudgetScreen extends ConsumerStatefulWidget {
  const HomeBudgetScreen({super.key});

  @override
  ConsumerState<HomeBudgetScreen> createState() => _HomeBudgetScreenState();
}

class _HomeBudgetScreenState extends ConsumerState<HomeBudgetScreen> {
  late int _year;
  late int _month;
  final _amount = TextEditingController();
  String? _source;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(financeRepositoryProvider);
    await repo.refresh();
    final override = await repo.budgetFor(_year, _month);
    final fallback = ref.read(sessionProvider).user?.defaultHomeBudget ?? '30000.00';
    if (mounted) {
      setState(() {
        _amount.text = override?.amount ?? fallback;
        _source = override == null ? 'Default owner budget' : 'Month override';
      });
    }
  }

  Future<void> _save() async {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(_amount.text.trim())) {
      setState(() => _error = 'Enter a valid budget amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(financeRepositoryProvider).saveBudget(
            year: _year,
            month: _month,
            amount: moneyFromDouble(moneyToDouble(_amount.text)),
          );
      if (mounted) {
        showAppSnack(context, 'Budget saved.');
        appPop(context, fallback: '/home');
      }
    } catch (error) {
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/home'),
        title: const AppBarTitle('Monthly budget'),
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 12, bottom: 8),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _month,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    for (var month = 1; month <= 12; month++)
                      DropdownMenuItem(
                        value: month,
                        child: Text(DateFormat.MMM().format(DateTime(2020, month))),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _month = value);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _year,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Year'),
                  items: [
                    for (var year = DateTime.now().year - 2; year <= DateTime.now().year + 1; year++)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _year = value);
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_source != null) StatusBanner(message: _source!, tone: StatusTone.info),
          const SizedBox(height: 12),
          if (_error != null) ErrorBanner(message: _error!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _save(),
                decoration: const InputDecoration(labelText: 'Budget amount', prefixIcon: Icon(Icons.payments_outlined)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Stretch(
            child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save budget')),
          ),
        ],
        ),
      ),
    );
  }
}
