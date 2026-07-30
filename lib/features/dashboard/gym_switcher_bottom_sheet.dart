import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/models/association_model.dart';
import '../authentication/auth_viewmodel.dart';
import '../authentication/first_time_setup_screen.dart';
import '../../core/navigation/app_router.dart';
import '../members/members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../workout/workout_viewmodel.dart';
import '../diet/diet_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';

class GymSwitcherBottomSheet extends StatelessWidget {
  const GymSwitcherBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const GymSwitcherBottomSheet(),
    );
  }

  Future<void> _reloadAllGymData(BuildContext context) async {
    // 1. Members & Transactions
    await Provider.of<MembersViewModel>(context, listen: false).fetchMembers();
    // 2. Staff
    await Provider.of<StaffViewModel>(context, listen: false).fetchStaff();
    // 3. Finance
    await Provider.of<FinanceViewModel>(context, listen: false).fetchTransactions();
    // 4. Membership
    await Provider.of<MembershipViewModel>(context, listen: false).loadPlans();
    
    // 5. Workouts, Diets, and Attendance just notify their listeners
    Provider.of<WorkoutViewModel>(context, listen: false).refresh();
    Provider.of<DietViewModel>(context, listen: false).refresh();
    Provider.of<AttendanceViewModel>(context, listen: false).refresh();
  }

  void _showSwitchConfirmation(
      BuildContext context, AuthViewModel authVm, UserGymAssociation assoc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Indicator line
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // Orange/Purple icon container
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    size: 32,
                    color: AppTheme.warning,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Switch Gym?',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'You are about to switch to\n'),
                      TextSpan(
                        text: assoc.gymName ?? 'Power Fitness',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const TextSpan(
                        text: '\nAll Members, Staff, Finance, Reports, Attendance and Settings will now be shown for this Gym only.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext); // Close confirmation
                          Navigator.pop(context); // Close switcher sheet
                          
                          // Switch Gym
                          await authVm.selectAssociation(assoc);
                          
                          // Refresh all UI view models
                          if (context.mounted) {
                            await _reloadAllGymData(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Switch Now',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final associations = authVm.userAssociations;
    final activeAssoc = authVm.activeAssociation;

    // Curated accent colors for gym avatars if they don't have custom logos
    final List<Color> avatarColors = [
      const Color(0xFF6C3AED), // Violet
      const Color(0xFFF59E0B), // Amber/Orange
      const Color(0xFFEF4444), // Red/Pink
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF10B981), // Green
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Top title & Create Gym button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'My Gyms',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context); // Close sheet
                        Navigator.push(
                          context,
                          AppRouter.scaleRoute(
                            const FirstTimeSetupScreen(isAddingAdditionalGym: true),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primary.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add, size: 14, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Add New Gym',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // List of Gyms
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20.0),
                  itemCount: associations.length,
                  itemBuilder: (context, index) {
                    final assoc = associations[index];
                    final isActive = activeAssoc?.gymId == assoc.gymId;
                    
                    // Choose unique color from preset list based on index
                    final avatarColor = avatarColors[index % avatarColors.length];
                    final firstLetter = (assoc.gymName ?? 'G').trim().toUpperCase().substring(0, 1);

                    return GestureDetector(
                      onTap: () {
                        if (!isActive) {
                          _showSwitchConfirmation(context, authVm, assoc);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primaryLight.withOpacity(0.3) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? AppTheme.primary : AppTheme.border,
                            width: isActive ? 1.5 : 1.0,
                          ),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Row(
                          children: [
                            // Gym Logo / Icon
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: avatarColor.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  firstLetter,
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: avatarColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Gym Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          assoc.gymName ?? 'FitZone Gym',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isActive) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            'Current',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'Surat, Gujarat', // Default city/state as placeholder or load dynamic city
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.circle,
                                        size: 4,
                                        color: AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surfaceGray,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Owner',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.primary,
                                size: 22,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              // Manage Gyms option at the bottom
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings_outlined, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Manage Gyms',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
