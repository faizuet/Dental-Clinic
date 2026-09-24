import 'package:intl/intl.dart';

String formatMoney(String amount, {String currency = 'PKR'}) {
  final value = double.tryParse(amount) ?? 0;
  final formatted = NumberFormat('#,##0.00').format(value);
  return '$currency $formatted';
}

double moneyToDouble(String amount) => double.tryParse(amount) ?? 0;

String moneyFromDouble(double value) => value.toStringAsFixed(2);

bool isValidMoney(String raw) {
  return RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw.trim()) && moneyToDouble(raw) > 0;
}

bool isValidQuantity(String raw) {
  return RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(raw.trim()) && moneyToDouble(raw) > 0;
}

String formatQuantity(String raw) {
  final text = moneyToDouble(raw).toStringAsFixed(3);
  return text.contains('.') ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : text;
}
