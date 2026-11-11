import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class ClinicMark extends StatelessWidget {
  const ClinicMark({super.key, required this.size, this.radius});

  static const asset = 'assets/icon/app_icon.png';

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.22),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.subtitle = 'Clinic management for laptop and desktop',
    this.compact = false,
  });

  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 48.0 : 72.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(compact ? AppRadii.md : AppRadii.lg), boxShadow: AppShadows.soft),
            child: ClinicMark(size: size, radius: compact ? AppRadii.md : AppRadii.lg),
          ),
          SizedBox(height: compact ? 12 : 18),
          Text(
            'Nabi Dental Clinic',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
