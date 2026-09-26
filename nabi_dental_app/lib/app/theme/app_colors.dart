import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF2F80ED);
  static const Color primaryDark = Color(0xFF1B6CDE);
  static const Color primarySoft = Color(0xFFE8F2FF);
  static const Color secondary = Color(0xFF5AA0FF);
  static const Color secondarySoft = Color(0xFFEDF5FF);
  static const Color background = Color(0xFFF3F7FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1B2430);
  static const Color muted = Color(0xFF7A8699);
  static const Color success = Color(0xFF2F9E6A);
  static const Color successSoft = Color(0xFFE5F7EE);
  static const Color danger = Color(0xFFD64545);
  static const Color dangerSoft = Color(0xFFFDECEC);
  static const Color warning = Color(0xFFE09B2D);
  static const Color warningSoft = Color(0xFFFDF3E1);
  static const Color border = Color(0xFFE4ECF6);
  static const Color inputFill = Color(0xFFF7FAFF);
  static const Color overlay = Color(0x1A2F80ED);
  static const Color shadow = Color(0x14203355);

  static const Color purple = primary;
  static const Color purpleSoft = primarySoft;
  static const Color pink = secondary;
  static const Color pinkSoft = secondarySoft;
  static const Color teal = Color(0xFF3D8BFF);
  static const Color tealSoft = Color(0xFFEAF3FF);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double page = 20;
  static const double tap = 48;
  static const double maxContent = 720;
}

class AppRadii {
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 28;
  static const double full = 999;
}

class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> soft = [
    BoxShadow(color: AppColors.overlay, blurRadius: 12, offset: Offset(0, 4)),
  ];
}

class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve accelerate = Curves.easeInCubic;

  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
