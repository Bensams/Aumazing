import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/parent_mode_top_bar.dart';
import '../splash/auth/login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: ParentModeTopBar(
        title: 'Aumazing',
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: Center(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.mintLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 40,
                      color: AppColors.mint,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Welcome!',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    user?.email ?? 'Signed in',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
