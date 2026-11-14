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

  ({String text, IconData icon, Color color}) get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return (text: 'Good Morning', icon: Icons.wb_sunny_rounded, color: AppColors.warning);
    }
    if (hour < 17) {
      return (text: 'Good Afternoon', icon: Icons.wb_sunny_outlined, color: AppColors.warning);
    }
    return (text: 'Good Evening', icon: Icons.nights_stay_rounded, color: AppColors.violet);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final art = MediaQuery.sizeOf(context).width >= 1000;
    final dateLabel = DateFormat('EEE, d MMM').format(DateTime.now());
    final greeting = _greeting;
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
              child: _blob(160, AppColors.primary.withValues(alpha: 0.08)),
            ),
            Positioned(
              left: 88,
              top: -28,
              child: _blob(72, AppColors.primary.withValues(alpha: 0.05)),
            ),
            if (art)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 360,
                child: IgnorePointer(child: _clinicArt()),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
              child: Row(
                children: [
                  _iconBadge(),
                  const SizedBox(width: 18),
                  Container(width: 1, height: 64, color: AppColors.primary.withValues(alpha: 0.18)),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                greeting.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(greeting.icon, size: 18, color: greeting.color),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.text,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
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
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondary, AppColors.primaryDark],
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }

  Widget _clinicArt() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.transparent, Colors.white],
        stops: [0.0, 0.35],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.22)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 150,
              bottom: -6,
              child: Icon(Icons.airline_seat_recline_extra_rounded, size: 120, color: AppColors.primary.withValues(alpha: 0.30)),
            ),
            Positioned(
              right: 96,
              top: 6,
              child: Icon(Icons.light_rounded, size: 56, color: AppColors.primary.withValues(alpha: 0.26)),
            ),
            Positioned(
              right: 30,
              bottom: 18,
              child: Icon(Icons.medical_services_rounded, size: 52, color: AppColors.primary.withValues(alpha: 0.22)),
            ),
          ],
        ),
      ),
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
