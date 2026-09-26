import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_colors.dart';

Page<void> buildAppPage(GoRouterState state, Widget child) {
  if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
    return CupertinoPage<void>(key: state.pageKey, child: child);
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.medium,
    reverseTransitionDuration: AppMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, page) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.standard, reverseCurve: AppMotion.accelerate);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
          child: page,
        ),
      );
    },
  );
}

GoRoute appRoute(String path, Widget Function() builder) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => buildAppPage(state, builder()),
  );
}
