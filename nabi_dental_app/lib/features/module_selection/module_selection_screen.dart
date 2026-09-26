import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/summary_card.dart';
import '../../core/widgets/welcome_header.dart';

class ModuleSelectionScreen extends ConsumerWidget {
  const ModuleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final clinic = session.clinic?.name ?? 'Nabi Dental Clinic';
    final name = session.user?.fullName ?? 'there';

    return AppExitScope(
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitle('Home'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: () => appPush(context, '/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: AppPageBody(
          child: ListView(
            children: [
              AppReveal(
                child: WelcomeHeader(
                  title: 'Hello, $name',
                  subtitle: clinic,
                  trailing: CircleAvatar(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Choose a module',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              AppReveal(
                index: 1,
                child: ActionCard(
                  title: 'Clinic Finance',
                  subtitle: 'Income, expenses, profit, and reports',
                  icon: Icons.local_hospital_rounded,
                  onTap: () => appPush(context, '/clinic'),
                ),
              ),
              AppReveal(
                index: 2,
                child: ActionCard(
                  title: 'Home Finance',
                  subtitle: 'Household expenses, budgets, and leftover',
                  icon: Icons.home_rounded,
                  color: AppColors.secondary,
                  soft: AppColors.secondarySoft,
                  onTap: () => appPush(context, '/home'),
                ),
              ),
              AppReveal(
                index: 3,
                child: ActionCard(
                  title: 'Construction Finance',
                  subtitle: 'House materials, quantities, and purchase history',
                  icon: Icons.foundation_rounded,
                  color: AppColors.teal,
                  soft: AppColors.tealSoft,
                  onTap: () => appPush(context, '/construction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
