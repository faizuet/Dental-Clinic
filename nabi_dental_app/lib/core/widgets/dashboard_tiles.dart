import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'app_controls.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
    this.actionLabel = 'View details',
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Ink(
            height: 128,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: color.withValues(alpha: 0.14)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, background],
              ),
              boxShadow: AppShadows.card,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -8,
                  bottom: -10,
                  child: Icon(icon, size: 76, color: color.withValues(alpha: 0.08)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedSwitcher(
                                  duration: AppMotion.of(context, AppMotion.medium),
                                  child: FittedBox(
                                    key: ValueKey(value),
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (onTap != null)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadii.full),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  actionLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, size: 13, color: color),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          splashColor: Colors.white.withValues(alpha: 0.16),
          child: Ink(
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: colors),
              boxShadow: [
                BoxShadow(color: colors.last.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({super.key, required this.title, required this.child, this.actionLabel, this.onAction});

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(actionLabel!),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 15),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
