import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

class AuthPageView extends StatelessWidget {
  final AuthService authService;
  final VoidCallback onAuthenticated;
  final VoidCallback onBack;

  const AuthPageView({
    super.key,
    required this.authService,
    required this.onAuthenticated,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authService,
      builder: (context, _) {
        final isAuthenticated = authService.isAuthenticated;
        final isSigningIn = authService.status == AuthStatus.signingIn;
        final user = authService.user;
        final verState = authService.verificationState;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Top back button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onBack,
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        label: Text(
                          'Back to Device',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Brand Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.iphoneBlue.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.iphoneBlue,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Text(
                      'Account Authorization',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in with your 414Unlock account to verify ownership and authorize unlock services.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Main Card
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: AppColors.liquidGlassDecoration(
                        radius: 16,
                        elevated: true,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isAuthenticated) ...[
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.iphoneBlue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.account_circle_outlined,
                                    color: AppColors.iphoneBlue,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Official Website Authorization',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Click below to open the secure authorization page in your browser.',
                                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (isSigningIn) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardElevated,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Waiting for sign-in completion in your browser...',
                                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: AppButton(
                                text: isSigningIn ? 'Open Browser Again' : 'Sign In / Register',
                                icon: Icons.open_in_browser_rounded,
                                variant: AppButtonVariant.primary,
                                isLoading: isSigningIn,
                                onPressed: () => authService.startWebSignIn(),
                              ),
                            ),
                          ] else ...[
                            // Authenticated User Details
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Signed in as ${user?.email ?? "Authorized Customer"}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => authService.signOut(),
                                  child: Text('Sign Out', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: AppColors.cardBorder),
                            const SizedBox(height: 16),

                            // Verification Status Row
                            _buildVerificationBadge(verState, authService.verificationNote),
                            const SizedBox(height: 24),

                            // Continue button
                            SizedBox(
                              width: double.infinity,
                              child: AppButton(
                                text: 'Continue with Unlock',
                                icon: Icons.arrow_forward_rounded,
                                variant: AppButtonVariant.primary,
                                onPressed: onAuthenticated,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (authService.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                authService.errorMessage,
                                style: const TextStyle(fontSize: 12, color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerificationBadge(VerificationState state, String note) {
    Color color;
    String title;
    String desc;
    IconData icon;

    switch (state) {
      case VerificationState.approved:
        color = AppColors.success;
        title = 'Device Ownership Verified';
        desc = 'Your account has verified device ownership.';
        icon = Icons.verified_rounded;
        break;
      case VerificationState.pending:
        color = AppColors.warning;
        title = 'Verification Pending Review';
        desc = 'Your ownership verification is being reviewed.';
        icon = Icons.hourglass_empty_rounded;
        break;
      case VerificationState.rejected:
        color = AppColors.error;
        title = 'Verification Not Approved';
        desc = note.isNotEmpty ? note : 'Ownership documentation was not approved.';
        icon = Icons.cancel_outlined;
        break;
      case VerificationState.notSubmitted:
      case VerificationState.unknown:
        color = AppColors.iphoneBlue;
        title = 'Verification Required';
        desc = 'Ownership verification required on the 414Unlock website.';
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}