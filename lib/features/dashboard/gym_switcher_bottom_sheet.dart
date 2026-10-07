import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/models/association_model.dart';
import '../../core/models/user_profile.dart';
import '../authentication/auth_viewmodel.dart';
import '../authentication/first_time_setup_screen.dart';
import '../authentication/role_selection_screen.dart';
import '../../core/navigation/app_router.dart';
import '../members/members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../workout/workout_viewmodel.dart';
import '../diet/diet_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import '../member_app/member_app_viewmodel.dart';
import '../members/trial_members_viewmodel.dart';
import '../../core/repository/gym_repository.dart';
import 'package:intl/intl.dart';
import 'main_navigation_holder.dart';

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

  Future<void> _reloadAllGymData(BuildContext navContext, UserGymAssociation assoc) async {
    final role = assoc.role;
    final gymId = assoc.gymId;

    // 0. Reset all viewmodel states first to clear any stale cache
    final membersVm = Provider.of<MembersViewModel>(navContext, listen: false);
    final trialMembersVm = Provider.of<TrialMembersViewModel>(navContext, listen: false);
    final staffVm = Provider.of<StaffViewModel>(navContext, listen: false);
    final financeVm = Provider.of<FinanceViewModel>(navContext, listen: false);
    final membershipVm = Provider.of<MembershipViewModel>(navContext, listen: false);
    final memberAppVm = Provider.of<MemberAppViewModel>(navContext, listen: false);
    final workoutVm = Provider.of<WorkoutViewModel>(navContext, listen: false);
    final dietVm = Provider.of<DietViewModel>(navContext, listen: false);
    final attendanceVm = Provider.of<AttendanceViewModel>(navContext, listen: false);
    final repo = Provider.of<GymRepository>(navContext, listen: false);

    membersVm.clearAllData();
    staffVm.clearAllData();
    memberAppVm.clearAllDataInMemory();
    repo.clearAllData();

    await repo.reloadForActiveGym();

    if (role == UserRole.member) {
      await memberAppVm.loadMemberDataFromSupabase();
      await repo.fetchAttendanceLogsFromSupabase();
    } else if (role == UserRole.owner) {
      // 1. Members & Trials
      await membersVm.fetchMembers();
      await trialMembersVm.fetchTrialMembers();
      // 2. Staff
      await staffVm.fetchStaff();
      // 3. Finance & Plans
      await financeVm.fetchTransactions();
      await membershipVm.loadPlans();
      
      // 4. Dashboard Stats & Analytics for the new gym
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await repo.fetchDashboardStatsFromSupabase(gymId, todayStr);
      await repo.fetchReportsAnalyticsFromSupabase(gymId, todayStr);
      await repo.fetchOwnerDashboardStats(gymId);
      await repo.fetchRecentActivitiesFromSupabase();
      await repo.fetchAttendanceSettingsFromSupabase();
      await repo.fetchAttendanceLogsFromSupabase();
      
      // 5. Workouts, Diets, and Attendance
      workoutVm.refresh();
      dietVm.refresh();
      attendanceVm.refresh();
    } else if (role == UserRole.staff) {
      // 1. Staff, Members & Trials
      await staffVm.fetchStaff();
      await membersVm.fetchMembers();
      await trialMembersVm.fetchTrialMembers();

      // 2. Finance & Plans (Receptionist dashboard)
      await financeVm.fetchTransactions();
      await membershipVm.loadPlans();

      // 3. Dashboard Stats, Attendance & Analytics
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await repo.fetchDashboardStatsFromSupabase(gymId, todayStr);
      await repo.fetchAttendanceSettingsFromSupabase();
      await repo.fetchAttendanceLogsFromSupabase();
      await repo.fetchRecentActivitiesFromSupabase();
      await repo.fetchOwnerDashboardStats(gymId);

      // 4. Workouts, Diets, and Attendance
      workoutVm.refresh();
      dietVm.refresh();
      attendanceVm.refresh();
    }
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
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
                  'Switch Profile?',
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
                        text: '${assoc.gymName ?? 'GYMOS'} (${assoc.role == UserRole.owner ? 'Owner' : assoc.role == UserRole.staff ? 'Staff' : 'Member'})',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const TextSpan(
                        text: '\nYour dashboard and data views will change to match this role and gym context.',
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

                          final rootNavState = AppRouter.rootNavigatorKey.currentState;
                          final rootCtx = AppRouter.rootNavigatorKey.currentContext;
                          if (rootCtx == null || rootNavState == null) return;

                          // Show non-dismissible loading overlay
                          showDialog(
                            context: rootCtx,
                            barrierDismissible: false,
                            builder: (dialogCtx) => PopScope(
                              canPop: false,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Switching profile...',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );

                          try {
                            // Switch gym/profile context
                            await authVm.selectAssociation(assoc);

                            // Reload all background data for the newly active gym
                            final activeContext = AppRouter.rootNavigatorKey.currentContext;
                            if (activeContext != null) {
                              await _reloadAllGymData(activeContext, assoc);
                            }

                            Widget targetScreen;
                            switch (assoc.role) {
                              case UserRole.owner:
                                if (assoc.setupCompleted) {
                                  targetScreen = MainNavigationHolder(key: UniqueKey());
                                } else {
                                  targetScreen = const FirstTimeSetupScreen();
                                }
                                break;
                              case UserRole.staff:
                                final staffRole = authVm.staffRecord?.role.toLowerCase() ?? '';
                                if (staffRole.contains('reception')) {
                                  targetScreen = ReceptionistShell(key: UniqueKey());
                                } else {
                                  targetScreen = StaffShell(key: UniqueKey());
                                }
                                break;
                              case UserRole.member:
                                targetScreen = MemberShell(key: UniqueKey());
                                break;
                            }

                            rootNavState.pushAndRemoveUntil(
                              AppRouter.scaleRoute(targetScreen),
                              (route) => false,
                            );
                          } catch (e) {
                            debugPrint('Error switching association: $e');
                            if (rootNavState.canPop()) {
                              rootNavState.pop();
                            }
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
    final activeAssoc = authVm.activeAssociation;
    final associations = authVm.userAssociations;

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
              // Top title & Create Gym/Profile button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'My Profiles',
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
                            const RoleSelectionScreen(isAddProfile: true),
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
                              'Add Profile',
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
              // List of Profiles
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20.0),
                  itemCount: associations.length,
                  itemBuilder: (context, index) {
                    final assoc = associations[index];
                    final isActive = activeAssoc?.gymId == assoc.gymId && activeAssoc?.role == assoc.role;
                    
                    IconData icon;
                    Color accentColor;
                    String roleLabel;

                    switch (assoc.role) {
                      case UserRole.owner:
                        icon = Icons.business_center_rounded;
                        accentColor = const Color(0xFF6C3AED); // Violet
                        roleLabel = 'Gym Owner';
                        break;
                      case UserRole.staff:
                        icon = Icons.badge_rounded;
                        accentColor = const Color(0xFFF59E0B); // Amber/Orange
                        roleLabel = 'Gym Staff';
                        break;
                      case UserRole.member:
                        icon = Icons.person_rounded;
                        accentColor = const Color(0xFF10B981); // Green
                        roleLabel = 'Gym Member';
                        break;
                    }

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
                            // Profile Role Icon Avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: accentColor, size: 20),
                            ),
                            const SizedBox(width: 16),
                            // Profile Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          assoc.gymName ?? 'GYMOS',
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
                                        roleLabel,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.circle,
                                        size: 4,
                                        color: AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        assoc.gymCode ?? 'MOCK123',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
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
              // Manage Profiles option at the bottom
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings_outlined, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Manage Profiles',
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
