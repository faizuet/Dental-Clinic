import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/models/finance_models.dart';
import '../../core/widgets/app_layout.dart';

const constructionCategoryOrder = [
  'Structure',
  'Woodwork',
  'Electrical',
  'Plumbing',
  'Finishing',
  'Sanitary',
  'Other',
];

IconData constructionCategoryIcon(String? category) {
  switch (category) {
    case 'Structure':
      return Icons.foundation_rounded;
    case 'Woodwork':
      return Icons.door_sliding_outlined;
    case 'Electrical':
      return Icons.electrical_services_rounded;
    case 'Plumbing':
      return Icons.water_drop_outlined;
    case 'Finishing':
      return Icons.format_paint_outlined;
    case 'Sanitary':
      return Icons.bathtub_outlined;
    default:
      return Icons.handyman_outlined;
  }
}

class ConstructionMaterialField extends StatelessWidget {
  const ConstructionMaterialField({
    super.key,
    required this.materials,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ConstructionMaterial> materials;
  final String? selectedId;
  final ValueChanged<ConstructionMaterial> onSelected;

  ConstructionMaterial? get selected {
    if (selectedId == null) {
      return null;
    }
    for (final item in materials) {
      if (item.id == selectedId) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = selected;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: materials.isEmpty
            ? null
            : () async {
                final picked = await showConstructionMaterialPicker(
                  context: context,
                  materials: materials,
                  selectedId: selectedId,
                );
                if (picked != null) {
                  onSelected(picked);
                }
              },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Material',
            suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
          ),
          child: item == null
              ? Text(
                  'Choose a material',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                )
              : Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.tealSoft,
                      foregroundColor: AppColors.teal,
                      child: Icon(constructionCategoryIcon(item.categoryName), size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${item.categoryName ?? 'Other'}  ·  ${item.unit}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

Future<ConstructionMaterial?> showConstructionMaterialPicker({
  required BuildContext context,
  required List<ConstructionMaterial> materials,
  String? selectedId,
}) {
  return showModalBottomSheet<ConstructionMaterial>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (context) {
      return _MaterialPickerSheet(materials: materials, selectedId: selectedId);
    },
  );
}

class _MaterialPickerSheet extends StatefulWidget {
  const _MaterialPickerSheet({required this.materials, required this.selectedId});

  final List<ConstructionMaterial> materials;
  final String? selectedId;

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final names = widget.materials.map((item) => item.categoryName ?? 'Other').toSet().toList();
    names.sort((a, b) {
      final left = constructionCategoryOrder.indexOf(a);
      final right = constructionCategoryOrder.indexOf(b);
      return (left < 0 ? 99 : left).compareTo(right < 0 ? 99 : right);
    });
    return names;
  }

  List<ConstructionMaterial> get _visible {
    final needle = _search.text.trim().toLowerCase();
    return widget.materials.where((item) {
      final category = item.categoryName ?? 'Other';
      if (_category != null && category != _category) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(needle) ||
          category.toLowerCase().contains(needle) ||
          item.unit.toLowerCase().contains(needle);
    }).toList();
  }

  Map<String, List<ConstructionMaterial>> get _grouped {
    final groups = <String, List<ConstructionMaterial>>{};
    for (final item in _visible) {
      groups.putIfAbsent(item.categoryName ?? 'Other', () => []).add(item);
    }
    for (final items in groups.values) {
      items.sort((a, b) => a.name.compareTo(b.name));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.86;
    final groups = _grouped;
    final categories = [
      for (final name in constructionCategoryOrder)
        if (groups.containsKey(name)) name,
      ...groups.keys.where((name) => !constructionCategoryOrder.contains(name)),
    ];

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 0, AppLayout.horizontalPadding(context), 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose material', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Search or browse by category',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Search materials',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: 'All',
                        selected: _category == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final name in _categories) ...[
                        const SizedBox(width: 8),
                        _CategoryChip(
                          label: name,
                          selected: _category == name,
                          onTap: () => setState(() => _category = name),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Text(
                      'No materials match that search.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      AppLayout.horizontalPadding(context),
                      8,
                      AppLayout.horizontalPadding(context),
                      24,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final items = groups[category] ?? [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(constructionCategoryIcon(category), size: 18, color: AppColors.teal),
                                const SizedBox(width: 8),
                                Text(category, style: Theme.of(context).textTheme.titleSmall),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final item in items)
                              Card(
                                child: ListTile(
                                  onTap: () => Navigator.pop(context, item),
                                  leading: CircleAvatar(
                                    backgroundColor: item.id == widget.selectedId ? AppColors.teal : AppColors.tealSoft,
                                    foregroundColor: item.id == widget.selectedId ? Colors.white : AppColors.teal,
                                    child: Text(item.name.isEmpty ? '?' : item.name[0].toUpperCase()),
                                  ),
                                  title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text('Sold by ${item.unit}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: item.id == widget.selectedId
                                      ? const Icon(Icons.check_circle_rounded, color: AppColors.teal)
                                      : const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.tealSoft,
      labelStyle: TextStyle(
        color: selected ? AppColors.teal : AppColors.text,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? AppColors.teal : AppColors.border),
      showCheckmark: false,
    );
  }
}
