import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import 'app_layout.dart';

void appPush(BuildContext context, String location) {
  context.push(location);
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

Future<bool> showExitAppDialog(BuildContext context) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return AlertDialog(
        title: const Text('Do you want to exit the app?'),
        content: const Text('You can open Nabi Dental again from the home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exit'),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
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

Future<bool> confirmDiscardChanges(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: 'Discard changes?',
    content: const Text('Your unsaved entries will be lost.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
    ],
  );
  return result ?? false;
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
