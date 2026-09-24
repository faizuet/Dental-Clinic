import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';

void main() {
  test('parses login profile payloads', () {
    final user = UserProfile.fromJson({
      'id': '8c2f0d7a-1b2c-4d5e-8f90-1234567890ab',
      'full_name': 'Clinic Owner',
      'email': 'owner@example.com',
      'role': 'owner',
      'default_home_budget': '75000.00',
    });
    final clinic = ClinicProfile.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Nabi Dental Clinic',
      'currency': 'PKR',
      'timezone': 'Asia/Karachi',
    });

    expect(user.fullName, 'Clinic Owner');
    expect(user.defaultHomeBudget, '75000.00');
    expect(user.hasAvatar, isFalse);
    expect(clinic.currency, 'PKR');
    expect(clinic.toJson()['timezone'], 'Asia/Karachi');
  });

  test('reads has_avatar from settings payloads', () {
    final user = UserProfile.fromJson({
      'id': '8c2f0d7a-1b2c-4d5e-8f90-1234567890ab',
      'full_name': 'Clinic Owner',
      'email': 'owner@example.com',
      'role': 'owner',
      'default_home_budget': '75000.00',
      'has_avatar': true,
    });
    expect(user.hasAvatar, isTrue);
    expect(user.copyWith(hasAvatar: false).hasAvatar, isFalse);
  });
}
