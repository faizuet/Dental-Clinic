import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'app_controls.dart';
import 'app_layout.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.color = AppColors.primary,
    this.soft = AppColors.primarySoft,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 640;
    final heading = Row(
      children: [
        Container(
          width: compact ? 48 : 60,
          height: compact ? 48 : 60,
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: color, size: compact ? 24 : 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: compact ? 21 : 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: compact || actions.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({super.key, required this.label, required this.icon, required this.onPressed, this.color});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color ?? AppColors.primary,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        elevation: 3,
        shadowColor: (color ?? AppColors.primary).withValues(alpha: 0.4),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class MiniStat {
  const MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.soft,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color soft;
  final String? caption;
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items, this.minItemWidth = 210});

  final List<MiniStat> items;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: ResponsiveGrid(
        minItemWidth: minItemWidth,
        spacing: 10,
        runSpacing: 10,
        children: [for (final item in items) _MiniStatTile(item: item)],
      ),
    );
  }
}

class _MiniStatTile extends StatelessWidget {
  const _MiniStatTile({required this.item});

  final MiniStat item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        gradient: LinearGradient(colors: [item.soft, item.soft.withValues(alpha: 0.45)]),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 6,
            bottom: -8,
            child: Icon(item.icon, size: 60, color: item.color.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: item.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(item.icon, color: item.color, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.value,
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.caption != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                    child: Text(
                      item.caption!,
                      style: theme.textTheme.labelSmall?.copyWith(color: item.color, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.filters, this.trailing = const []});

  final List<Widget> filters;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          if (!wide) {
            return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [...filters, ...trailing]);
          }
          return Row(
            children: [
              for (var i = 0; i < filters.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                filters[i] is FilterSearch ? Expanded(child: filters[i]) : filters[i],
              ],
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 10),
                for (var i = 0; i < trailing.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  trailing[i],
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class FilterSearch extends StatelessWidget {
  const FilterSearch({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: SizedBox(
        height: 46,
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.full),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.full),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.full),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.label, required this.icon, required this.onPressed, this.trailingIcon});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 18),
          ],
        ],
      ),
    );
  }
}

class SegmentPills<T> extends StatelessWidget {
  const SegmentPills({super.key, required this.options, required this.value, required this.onChanged});

  final List<({T value, String label})> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _Pill(
            label: option.label,
            selected: option.value == value,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.card,
      elevation: selected ? 3 : 0,
      shadowColor: AppColors.primary.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.full),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.full),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

class TablePanel extends StatelessWidget {
  const TablePanel({super.key, required this.child, this.header, this.footer});

  final Widget child;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[
              header!,
              const Divider(height: 1),
            ],
            child,
            if (footer != null) ...[
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 14), child: footer),
            ],
          ],
        ),
      ),
    );
  }
}

class TableFooterText extends StatelessWidget {
  const TableFooterText({super.key, required this.shown, required this.total, required this.noun, this.trailing});

  final int shown;
  final int total;
  final String noun;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = total == 0 ? 'No $noun' : 'Showing ${shown == 0 ? 0 : 1} to $shown of $total $noun';
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class RowAction extends StatelessWidget {
  const RowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.primary,
    this.soft = AppColors.primarySoft,
  });

  const RowAction.danger({super.key, required this.icon, required this.tooltip, required this.onPressed})
      : color = AppColors.danger,
        soft = AppColors.dangerSoft;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: onPressed == null ? AppColors.border.withValues(alpha: 0.5) : soft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: color.withValues(alpha: 0.10),
            onTap: onPressed,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 19, color: onPressed == null ? AppColors.muted : color),
            ),
          ),
        ),
      ),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  static const _palette = [
    (AppColors.primary, AppColors.primarySoft),
    (AppColors.violet, AppColors.violetSoft),
    (AppColors.success, AppColors.successSoft),
    (AppColors.orange, AppColors.warningSoft),
    (AppColors.aqua, AppColors.aquaSoft),
  ];

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palette[name.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.$2, shape: BoxShape.circle),
      child: Text(
        initials(name),
        style: TextStyle(color: colors.$1, fontWeight: FontWeight.w800, fontSize: size * 0.36),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color = AppColors.success, this.soft = AppColors.successSoft});

  final String label;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(AppRadii.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class IconText extends StatelessWidget {
  const IconText({super.key, required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.navy.withValues(alpha: 0.8)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted ? const TextStyle(color: AppColors.muted) : null,
          ),
        ),
      ],
    );
  }
}

class PageScaffoldBody extends StatelessWidget {
  const PageScaffoldBody({super.key, required this.children, this.onRefresh});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppLayout.pagePadding(context, top: 4, bottom: 28),
      children: children,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppLayout.maxContent(context)),
        child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

class PanelTitle extends StatelessWidget {
  const PanelTitle({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.color = AppColors.primary,
    this.soft = AppColors.primarySoft,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final Color color;
  final Color soft;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class SkeletonTable extends StatelessWidget {
  const SkeletonTable({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.all(16), child: SkeletonCards(count: 3));
  }
}
