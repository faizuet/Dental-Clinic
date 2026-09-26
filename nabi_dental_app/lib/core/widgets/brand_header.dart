import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.subtitle = 'Private finance for the clinic and home',
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
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(compact ? AppRadii.md : AppRadii.lg),
              boxShadow: AppShadows.soft,
            ),
            child: Icon(Icons.local_hospital_rounded, color: Colors.white, size: compact ? 24 : 34),
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
