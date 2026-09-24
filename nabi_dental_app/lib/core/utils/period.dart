enum FinancePeriod { daily, monthly, yearly, custom }

class DateRange {
  const DateRange({required this.from, required this.to, required this.period});

  final DateTime from;
  final DateTime to;
  final FinancePeriod period;

  String get fromIso => _iso(from);
  String get toIso => _iso(to);

  static String _iso(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateRange forPeriod(FinancePeriod period, {DateTime? now, DateTime? customFrom, DateTime? customTo}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    switch (period) {
      case FinancePeriod.daily:
        return DateRange(from: day, to: day, period: period);
      case FinancePeriod.monthly:
        final start = DateTime(day.year, day.month, 1);
        final end = DateTime(day.year, day.month + 1, 0);
        return DateRange(from: start, to: end, period: period);
      case FinancePeriod.yearly:
        return DateRange(from: DateTime(day.year, 1, 1), to: DateTime(day.year, 12, 31), period: period);
      case FinancePeriod.custom:
        final from = customFrom ?? DateTime(day.year, day.month, 1);
        final to = customTo ?? day;
        return DateRange(from: from, to: to, period: period);
    }
  }

  bool containsIso(String date) => date.compareTo(fromIso) >= 0 && date.compareTo(toIso) <= 0;
}
