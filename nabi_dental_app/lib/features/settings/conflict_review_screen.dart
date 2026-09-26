import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
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
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const AppBarTitle('Conflict review'),
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
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContent),
                    child: ListView.builder(
                  padding: AppLayout.pagePadding(context),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.entityType.replaceAll('_', ' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This device: ${_preview(item.local)}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Server: ${_preview(item.server)}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 12),
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
                    );
                  },
                ),
                  ),
                ),
    );
  }
}
