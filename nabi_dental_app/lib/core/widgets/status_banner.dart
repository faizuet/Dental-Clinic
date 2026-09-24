import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum StatusTone { error, offline, success, warning, info }

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.tone = StatusTone.error,
    this.icon,
    this.onRetry,
  });

  const StatusBanner.error(this.message, {super.key, this.onRetry})
      : tone = StatusTone.error,
        icon = Icons.error_outline_rounded;

  const StatusBanner.offline(this.message, {super.key, this.onRetry})
      : tone = StatusTone.offline,
        icon = Icons.cloud_off_outlined;

  const StatusBanner.success(this.message, {super.key, this.onRetry})
      : tone = StatusTone.success,
        icon = Icons.check_circle_outline_rounded;

  final String message;
  final StatusTone tone;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      StatusTone.error => (AppColors.dangerSoft, AppColors.danger),
      StatusTone.offline => (AppColors.warningSoft, AppColors.warning),
      StatusTone.success => (AppColors.successSoft, AppColors.success),
      StatusTone.warning => (AppColors.warningSoft, AppColors.warning),
      StatusTone.info => (AppColors.purpleSoft, AppColors.purple),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline_rounded, color: colors.$2, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.$2, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry', style: TextStyle(color: colors.$2, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

