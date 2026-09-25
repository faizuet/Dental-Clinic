import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/utils/period.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_selector.dart';
import '../../core/widgets/status_banner.dart';
import '../../core/widgets/summary_card.dart';

class ConstructionDashboardScreen extends ConsumerStatefulWidget {
  const ConstructionDashboardScreen({super.key});

  @override
  ConsumerState<ConstructionDashboardScreen> createState() => _ConstructionDashboardScreenState();
}

class _ConstructionDashboardScreenState extends ConsumerState<ConstructionDashboardScreen> {
  FinancePeriod _period = FinancePeriod.monthly;
  DateTime? _customFrom;
  DateTime? _customTo;
  ConstructionTotals? _totals;
  bool _loading = true;
  bool _online = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      var online = true;
      try {
        online = await repo.refresh();
      } catch (_) {
        online = false;
      }
      await repo.ensureConstructionCatalog();
      final range = DateRange.forPeriod(_period, customFrom: _customFrom, customTo: _customTo);
      final totals = await ref.read(financeRepositoryProvider).constructionTotals(range);
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/modules'),
        title: const AppBarTitle('Construction Finance'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 0, bottom: 8),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
            children: [
              PeriodSelector(
                value: _period,
                onChanged: (value) async {
                  if (value == FinancePeriod.custom) {
                    final from = await showDatePicker(
                      context: context,
                      initialDate: _customFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (from == null || !context.mounted) {
                      return;
                    }
                    final to = await showDatePicker(
                      context: context,
                      initialDate: _customTo ?? DateTime.now(),
                      firstDate: from,
                      lastDate: DateTime.now(),
                    );
                    if (to == null) {
                      return;
                    }
                    _customFrom = from;
                    _customTo = to;
                  }
                  setState(() => _period = value);
                  await _load();
                },
              ),
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                StatusBanner.error(_loadError!, onRetry: _load),
              ] else if (!_online) ...[
                const SizedBox(height: 12),
                StatusBanner.offline('Showing local construction records.', onRetry: _load),
              ],
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _loading
                    ? const LoadingView(message: 'Updating construction totals…')
                    : totals == null
                        ? const EmptyState(message: 'No construction totals yet.')
                        : Column(
                            key: const ValueKey('construction-totals'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SummaryCard(
                                label: 'Total construction expense',
                                value: formatMoney(totals.spent, currency: currency),
                                color: AppColors.teal,
                                icon: Icons.foundation_outlined,
                              ),
                              SummaryCard(
                                label: 'Material purchases',
                                value: '${totals.purchaseCount}',
                                color: AppColors.teal,
                                icon: Icons.inventory_2_outlined,
                              ),
                              _NamedList(
                                title: 'Expenses by category',
                                empty: 'No category spending in this period.',
                                items: totals.byCategory,
                                currency: currency,
                              ),
                              _NamedList(
                                title: 'Monthly spending',
                                empty: 'No monthly spending yet.',
                                items: totals.monthly,
                                currency: currency,
                              ),
                              _NamedList(
                                title: 'Highest-cost materials',
                                empty: 'No material costs in this period.',
                                items: totals.topMaterials,
                                currency: currency,
                              ),
                              const SectionHeader('Recent purchases'),
                              if (totals.recent.isEmpty)
                                const EmptyState(message: 'No purchases in this period yet.')
                              else
                                for (final item in totals.recent) _RecentPurchaseTile(item: item, currency: currency),
                            ],
                          ),
              ),
              const SectionHeader('Quick actions'),
              Stretch(
                child: FilledButton.icon(
                  onPressed: () => appPush(context, '/construction/purchases'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add material purchase', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 10),
              Stretch(
                child: OutlinedButton.icon(
                  onPressed: () => appPush(context, '/construction/materials'),
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('Manage materials', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 16),
              ActionCard(
                title: 'Purchase history',
                subtitle: 'Quantities, prices, suppliers, and notes',
                icon: Icons.history_rounded,
                color: AppColors.teal,
                soft: AppColors.tealSoft,
                onTap: () => appPush(context, '/construction/purchases/history'),
              ),
              ActionCard(
                title: 'Reports and exports',
                subtitle: 'Breakdowns, timeline, PDF and Excel',
                icon: Icons.picture_as_pdf_outlined,
                color: AppColors.teal,
                soft: AppColors.tealSoft,
                onTap: () => appPush(context, '/construction/reports'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NamedList extends StatelessWidget {
  const _NamedList({
    required this.title,
    required this.empty,
    required this.items,
    required this.currency,
  });

  final String title;
  final String empty;
  final List<NamedAmount> items;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
            ),
          )
        else
          for (final item in items)
            Card(
              child: ListTile(
                title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: MoneyText(
                    formatMoney(item.amount, currency: currency),
                    style: Theme.of(context).textTheme.titleSmall,
                    color: AppColors.teal,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _RecentPurchaseTile extends StatelessWidget {
  const _RecentPurchaseTile({required this.item, required this.currency});

  final ConstructionPurchase item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final detail = [
      item.date,
      '${formatQuantity(item.quantity)} ${item.unit}',
      if (item.supplier != null && item.supplier!.isNotEmpty) item.supplier,
    ].join(' · ');
    return Card(
      child: ListTile(
        title: Text(item.materialName ?? 'Material', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: MoneyText(
            formatMoney(item.amount, currency: currency),
            style: Theme.of(context).textTheme.titleSmall,
            color: AppColors.teal,
          ),
        ),
      ),
    );
  }
}
