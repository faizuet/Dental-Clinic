import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';

class ConflictReviewScreen extends ConsumerStatefulWidget {
  const ConflictReviewScreen({super.key});

  @override
  ConsumerState<ConflictReviewScreen> createState() => _ConflictReviewScreenState();
}

class _ConflictReviewScreenState extends ConsumerState<ConflictReviewScreen> {
  List<SyncConflict> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ref.read(financeRepositoryProvider).conflicts();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String _preview(Map<String, dynamic> value) {
    final amount = value['amount'];
    final date = value['transaction_date'] ?? value['expense_date'] ?? value['year'];
    final name = value['name'] ?? value['catalog_name'] ?? value['notes'] ?? '';
    return [
      if (amount != null) formatMoney(amount.toString()),
      if (date != null) formatDisplayDateLabel(date),
      if (name.toString().isNotEmpty) name.toString(),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Conflict review',
        fallback: '/settings',
      ),
      body: _loading
          ? const Center(child: LoadingView(message: 'Checking conflicts…'))
          : _items.isEmpty
              ? const Center(
                  child: EmptyState(
                    message: 'No synchronization conflicts right now.',
                    title: 'All clear',
                    icon: Icons.verified_outlined,
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: AppLayout.maxContent(context)),
                    child: ListView.builder(
                  padding: AppLayout.pagePadding(context),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TablePanel(
                      header: PanelTitle(
                        title: item.entityType.replaceAll('_', ' '),
                        subtitle: 'The saved values differ. Choose which one to keep.',
                        icon: Icons.merge_type_rounded,
                        color: AppColors.orange,
                        soft: AppColors.warningSoft,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _valueBox(Icons.computer_rounded, 'This device', _preview(item.local), AppColors.primarySoft),
                            const SizedBox(height: 10),
                            _valueBox(Icons.dns_rounded, 'Server', _preview(item.server), AppColors.aquaSoft),
                            const SizedBox(height: 16),
                            OverflowBar(
                              spacing: 8,
                              overflowSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () async {
                                    await ref.read(financeRepositoryProvider).resolveConflict(conflict: item, keepLocal: true);
                                    await _load();
                                  },
                                  child: const Text('Keep mine'),
                                ),
                                FilledButton(
                                  onPressed: () async {
                                    await ref.read(financeRepositoryProvider).resolveConflict(conflict: item, keepLocal: false);
                                    await _load();
                                  },
                                  child: const Text('Use server'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    );
                  },
                ),
                  ),
                ),
    );
  }

  Widget _valueBox(IconData icon, String label, String value, Color background) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
