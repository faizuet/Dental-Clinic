import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/summary_card.dart';

class ModuleSelectionScreen extends ConsumerWidget {
  const ModuleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final clinic = session.clinic?.name ?? 'Nabi Dental Clinic';

    return AppExitScope(
      child: Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Choose a module'),
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
            Text(
              clinic,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              session.user == null ? 'Signed in' : session.user!.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            ActionCard(
              title: 'Clinic Finance',
              subtitle: 'Income, expenses, profit, and reports',
              icon: Icons.local_hospital_rounded,
              color: AppColors.purple,
              soft: AppColors.purpleSoft,
              onTap: () => appPush(context, '/clinic'),
            ),
            ActionCard(
              title: 'Home Finance',
              subtitle: 'Household expenses, budgets, and leftover',
              icon: Icons.home_rounded,
              color: AppColors.pink,
              soft: AppColors.pinkSoft,
              onTap: () => appPush(context, '/home'),
            ),
            ActionCard(
              title: 'Construction Finance',
              subtitle: 'House materials, quantities, and purchase history',
              icon: Icons.foundation_rounded,
              color: AppColors.teal,
              soft: AppColors.tealSoft,
              onTap: () => appPush(context, '/construction'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
