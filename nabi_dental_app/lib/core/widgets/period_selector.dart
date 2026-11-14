import 'package:flutter/material.dart';

import '../utils/period.dart';
import 'page_kit.dart';

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
    return SegmentPills<FinancePeriod>(
      options: [for (final period in FinancePeriod.values) (value: period, label: _label(period))],
      value: value,
      onChanged: onChanged,
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
