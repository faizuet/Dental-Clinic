class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.defaultHomeBudget,
    this.hasAvatar = false,
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
  final String defaultHomeBudget;
  final bool hasAvatar;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      defaultHomeBudget: json['default_home_budget'].toString(),
      hasAvatar: json['has_avatar'] == true,
    );
  }

  UserProfile copyWith({
    String? fullName,
    String? email,
    String? defaultHomeBudget,
    bool? hasAvatar,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role,
      defaultHomeBudget: defaultHomeBudget ?? this.defaultHomeBudget,
      hasAvatar: hasAvatar ?? this.hasAvatar,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'role': role,
        'default_home_budget': defaultHomeBudget,
        'has_avatar': hasAvatar,
      };
}

class ClinicProfile {
  const ClinicProfile({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
  });

  final String id;
  final String name;
  final String currency;
  final String timezone;

  factory ClinicProfile.fromJson(Map<String, dynamic> json) {
    return ClinicProfile(
      id: json['id'].toString(),
      name: json['name'] as String,
      currency: json['currency'] as String,
      timezone: json['timezone'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currency': currency,
        'timezone': timezone,
      };
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}
