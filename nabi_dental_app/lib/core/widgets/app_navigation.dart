import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import 'app_layout.dart';

Future<T?> appPush<T extends Object?>(BuildContext context, String location) {
  return context.push<T>(location);
}

Future<void> appPushAndRefresh(
  BuildContext context,
  String location,
  Future<void> Function() refresh,
) async {
  await appPush(context, location);
  if (context.mounted) {
    await refresh();
  }
}

void appPop(BuildContext context, {String? fallback}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  if (fallback != null) {
    context.go(fallback);
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback});

  final String? fallback;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => appPop(context, fallback: fallback),
    );
  }
}

Future<bool> showExitAppDialog(BuildContext context) {
  return showAppConfirmDialog(
    context: context,
    title: 'Exit the app?',
    message: 'Are you sure you want to exit? You can open Nabi Dental again from the home screen.',
    cancelLabel: 'Cancel',
    confirmLabel: 'Exit',
    icon: Icons.logout_rounded,
  );
}

class AppExitScope extends StatelessWidget {
  const AppExitScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final shouldExit = await showExitAppDialog(context);
        if (shouldExit && context.mounted) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}

Future<bool> confirmDiscardChanges(BuildContext context) {
  return showAppConfirmDialog(
    context: context,
    title: 'Discard these changes?',
    message: 'What you typed will not be saved.',
    cancelLabel: 'Keep editing',
    confirmLabel: 'Discard',
    destructive: true,
    icon: Icons.edit_off_rounded,
  );
}

class AppDiscardScope extends StatefulWidget {
  const AppDiscardScope({
    super.key,
    required this.dirty,
    required this.child,
    this.fallback,
  });

  final bool dirty;
  final Widget child;
  final String? fallback;

  @override
  State<AppDiscardScope> createState() => _AppDiscardScopeState();
}

class _AppDiscardScopeState extends State<AppDiscardScope> {
  var _allowPop = false;

  Future<void> _confirmAndLeave() async {
    final discard = await confirmDiscardChanges(context);
    if (!discard || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        appPop(context, fallback: widget.fallback);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.dirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !widget.dirty || _allowPop) {
          return;
        }
        await _confirmAndLeave();
      },
      child: widget.child,
    );
  }
}

void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.text,
      ),
    );
}
