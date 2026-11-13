import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.waving_hand_rounded,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final dateLabel = DateFormat('EEE, d MMM').format(DateTime.now());
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      AppColors.secondarySoft,
                      AppColors.primarySoft,
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -36,
              top: -42,
              child: _blob(140, AppColors.primary.withValues(alpha: 0.10)),
            ),
            Positioned(
              right: 56,
              bottom: -48,
              child: _blob(110, AppColors.secondary.withValues(alpha: 0.14)),
            ),
            Positioned(
              left: 88,
              top: -28,
              child: _blob(72, AppColors.primary.withValues(alpha: 0.06)),
            ),
            Positioned(
              left: 0,
              top: 18,
              bottom: 18,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
              child: Row(
                children: [
                  _iconBadge(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.text,
                                fontSize: 22,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 12),
                    _dateChip(context, dateLabel),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBadge() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Icon(icon, color: AppColors.primary, size: 26),
    );
  }

  Widget _dateChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  static Widget _blob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
