DateTime? parseFlexibleDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) {
    return DateTime(iso.year, iso.month, iso.day);
  }
  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$').firstMatch(text);
  if (slash != null) {
    final day = int.parse(slash.group(1)!);
    final month = int.parse(slash.group(2)!);
    var year = int.parse(slash.group(3)!);
    if (year < 100) {
      year += 2000;
    }
    return DateTime(year, month, day);
  }
  return null;
}

String formatDisplayDate(Object? value) {
  final date = parseFlexibleDate(value);
  if (date == null) {
    return value?.toString() ?? '';
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = (date.year % 100).toString().padLeft(2, '0');
  return '$day/$month/$year';
}

String formatDisplayDateRange(Object? from, Object? to, {String separator = ' to '}) {
  return '${formatDisplayDate(from)}$separator${formatDisplayDate(to)}';
}

String formatDisplayDateLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(text)) {
    return '${text.substring(5)}/${text.substring(2, 4)}';
  }
  final formatted = formatDisplayDate(value);
  return formatted.isEmpty ? text : formatted;
}
