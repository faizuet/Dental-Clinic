import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../utils/period.dart';

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final FinancePeriod value;
  final ValueChanged<FinancePeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final period in FinancePeriod.values)
          ChoiceChip(
            label: Text(_label(period)),
            selected: value == period,
            showCheckmark: false,
            selectedColor: AppColors.purpleSoft,
            labelStyle: TextStyle(
              color: value == period ? AppColors.purple : AppColors.text,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onChanged(period),
          ),
      ],
    );
  }

  String _label(FinancePeriod period) {
    switch (period) {
      case FinancePeriod.daily:
        return 'Daily';
      case FinancePeriod.monthly:
        return 'Monthly';
      case FinancePeriod.yearly:
        return 'Yearly';
      case FinancePeriod.custom:
        return 'Custom';
    }
  }
}
