import 'package:flutter/services.dart';

const pakistaniMobileMessage = 'Enter an 11-digit Pakistani mobile number starting with 03.';

final _pakistaniMobile = RegExp(r'^03[0-9]{9}$');

final pakistaniMobileInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(11),
];

bool isPakistaniMobile(String? value) {
  final digits = value?.trim() ?? '';
  return _pakistaniMobile.hasMatch(digits);
}

String? validateOptionalPakistaniMobile(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  if (!isPakistaniMobile(trimmed)) {
    return pakistaniMobileMessage;
  }
  return null;
}
