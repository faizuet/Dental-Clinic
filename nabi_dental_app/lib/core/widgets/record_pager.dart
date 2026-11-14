import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

const int recordPageSize = 10;

class RecordPage<T> {
  const RecordPage({
    required this.items,
    required this.page,
    required this.pages,
    required this.start,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pages;
  final int start;
  final int total;

  int get from => total == 0 ? 0 : start + 1;
  int get to => start + items.length;

  static RecordPage<T> of<T>(List<T> source, int page, {int pageSize = recordPageSize}) {
    final size = pageSize < 1 ? recordPageSize : pageSize;
    final total = source.length;
    final pages = total == 0 ? 1 : ((total + size - 1) ~/ size);
    final safe = total == 0 ? 0 : page.clamp(0, pages - 1);
    final start = safe * size;
    final end = start + size > total ? total : start + size;
    return RecordPage(
      items: source.sublist(start, end),
      page: safe,
      pages: pages,
      start: start,
      total: total,
    );
  }
}

int settleRecordPage({
  required int page,
  required int previousCount,
  required int nextCount,
  int pageSize = recordPageSize,
}) {
  if (nextCount <= 0) {
    return 0;
  }
  final size = pageSize < 1 ? recordPageSize : pageSize;
  final pages = (nextCount + size - 1) ~/ size;
  if (nextCount > previousCount) {
    return 0;
  }
  if (page < 0) {
    return 0;
  }
  if (page >= pages) {
    return pages - 1;
  }
  return page;
}

List<int?> recordPageIndexes(int page, int pages) {
  if (pages <= 0) {
    return const [];
  }
  if (pages <= 7) {
    return [for (var index = 0; index < pages; index++) index];
  }
  final keep = <int>{0, pages - 1};
  for (var index = page - 1; index <= page + 1; index++) {
    if (index >= 0 && index < pages) {
      keep.add(index);
    }
  }
  if (page <= 2) {
    keep.addAll([1, 2, 3].where((index) => index < pages));
  }
  if (page >= pages - 3) {
    keep.addAll([pages - 2, pages - 3, pages - 4].where((index) => index >= 0));
  }
  final sorted = keep.toList()..sort();
  final result = <int?>[];
  for (var index = 0; index < sorted.length; index++) {
    if (index > 0 && sorted[index] != sorted[index - 1] + 1) {
      result.add(null);
    }
    result.add(sorted[index]);
  }
  return result;
}

class RecordPageBar<T> extends StatelessWidget {
  const RecordPageBar({
    super.key,
    required this.page,
    required this.noun,
    required this.onPage,
    this.trailing,
  });

  final RecordPage<T> page;
  final String noun;
  final ValueChanged<int> onPage;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = page.total == 0 ? 'No $noun' : 'Showing ${page.from}–${page.to} of ${page.total} $noun';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 8),
        ],
        if (page.total > recordPageSize)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PageStep(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous page',
                    onPressed: page.page == 0 ? null : () => onPage(page.page - 1),
                  ),
                  for (final index in recordPageIndexes(page.page, page.pages))
                    if (index == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('…', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                      )
                    else
                      _PageNumber(
                        label: '${index + 1}',
                        selected: index == page.page,
                        onPressed: () => onPage(index),
                      ),
                  _PageStep(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next page',
                    onPressed: page.page >= page.pages - 1 ? null : () => onPage(page.page + 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PageStep extends StatelessWidget {
  const _PageStep({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: onPressed == null ? AppColors.border.withValues(alpha: 0.45) : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 18, color: onPressed == null ? AppColors.muted : AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: 'Page $label',
        child: Material(
          color: selected ? AppColors.primary : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
