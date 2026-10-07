import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import '../../core/models/user_profile.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import '../member_app/member_app_viewmodel.dart';
import '../members/members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../workout/workout_viewmodel.dart';
import '../diet/diet_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';
import '../members/trial_members_viewmodel.dart';
import '../../core/repository/gym_repository.dart';
import 'package:intl/intl.dart';
import 'first_time_setup_screen.dart';
import 'role_selection_screen.dart';
import 'auth_viewmodel.dart';

class GymRoleSelectorScreen extends StatelessWidget {
  const GymRoleSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final associations = authVm.userAssociations;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Header
              Text(
                'Select Profile',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the gym account you want to enter',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Associations List
              Expanded(
                child: ListView.builder(
                  itemCount: associations.length,
                  itemBuilder: (context, index) {
                    final assoc = associations[index];
                    IconData icon;
                    Color accentColor;

                    switch (assoc.role) {
                      case UserRole.owner:
                        icon = Icons.business_center_rounded;
                        accentColor = AppTheme.primary;
                        break;
                      case UserRole.staff:
                        icon = Icons.badge_rounded;
                        accentColor = AppTheme.warning;
                        break;
                      case UserRole.member:
                        icon = Icons.person_rounded;
                        accentColor = const Color(0xFF10B981);
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () async {
                          final rootNavState = AppRouter.rootNavigatorKey.currentState;
                          final rootCtx = AppRouter.rootNavigatorKey.currentContext ?? context;

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
                            // Clear in-memory caches from previous role/profile
                            final membersVm = Provider.of<MembersViewModel>(rootCtx, listen: false);
                            final trialMembersVm = Provider.of<TrialMembersViewModel>(rootCtx, listen: false);
                            final staffVm = Provider.of<StaffViewModel>(rootCtx, listen: false);
                            final financeVm = Provider.of<FinanceViewModel>(rootCtx, listen: false);
                            final membershipVm = Provider.of<MembershipViewModel>(rootCtx, listen: false);
                            final memberAppVm = Provider.of<MemberAppViewModel>(rootCtx, listen: false);
                            final workoutVm = Provider.of<WorkoutViewModel>(rootCtx, listen: false);
                            final dietVm = Provider.of<DietViewModel>(rootCtx, listen: false);
                            final attendanceVm = Provider.of<AttendanceViewModel>(rootCtx, listen: false);
                            final repo = Provider.of<GymRepository>(rootCtx, listen: false);

                            membersVm.clearAllData();
                            staffVm.clearAllData();
                            memberAppVm.clearAllDataInMemory();
                            repo.clearAllData();

                            await authVm.selectAssociation(assoc);
                            await repo.reloadForActiveGym();

                            Widget targetScreen;
                            switch (assoc.role) {
                              case UserRole.owner:
                                if (assoc.setupCompleted) {
                                  targetScreen = MainNavigationHolder(key: UniqueKey());
                                } else {
                                  targetScreen = const FirstTimeSetupScreen();
                                }
                                await membersVm.fetchMembers();
                                await trialMembersVm.fetchTrialMembers();
                                await staffVm.fetchStaff();
                                await financeVm.fetchTransactions();
                                await membershipVm.loadPlans();
                                final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                await repo.fetchDashboardStatsFromSupabase(assoc.gymId, todayStr);
                                await repo.fetchReportsAnalyticsFromSupabase(assoc.gymId, todayStr);
                                await repo.fetchOwnerDashboardStats(assoc.gymId);
                                await repo.fetchRecentActivitiesFromSupabase();
                                await repo.fetchAttendanceSettingsFromSupabase();
                                await repo.fetchAttendanceLogsFromSupabase();
                                workoutVm.refresh();
                                dietVm.refresh();
                                attendanceVm.refresh();
                                break;
                              case UserRole.staff:
                                final staffRole = authVm.staffRecord?.role.toLowerCase() ?? '';
                                if (staffRole.contains('reception')) {
                                  targetScreen = ReceptionistShell(key: UniqueKey());
                                } else {
                                  targetScreen = StaffShell(key: UniqueKey());
                                }
                                await staffVm.fetchStaff();
                                await membersVm.fetchMembers();
                                await trialMembersVm.fetchTrialMembers();
                                await financeVm.fetchTransactions();
                                await membershipVm.loadPlans();
                                final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                await repo.fetchDashboardStatsFromSupabase(assoc.gymId, todayStr);
                                await repo.fetchAttendanceSettingsFromSupabase();
                                await repo.fetchAttendanceLogsFromSupabase();
                                await repo.fetchRecentActivitiesFromSupabase();
                                await repo.fetchOwnerDashboardStats(assoc.gymId);
                                workoutVm.refresh();
                                dietVm.refresh();
                                attendanceVm.refresh();
                                break;
                              case UserRole.member:
                                targetScreen = MemberShell(key: UniqueKey());
                                await memberAppVm.loadMemberDataFromSupabase();
                                await repo.fetchAttendanceLogsFromSupabase();
                                break;
                            }

                            if (rootNavState != null) {
                              rootNavState.pushAndRemoveUntil(
                                AppRouter.scaleRoute(targetScreen),
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            debugPrint('Error selecting role: $e');
                            if (rootNavState != null && rootNavState.canPop()) {
                              rootNavState.pop();
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(color: AppTheme.border, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(icon, color: accentColor, size: 26),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      assoc.gymName ?? 'GymOS Partner',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentColor.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        assoc.role.name.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: AppTheme.textMuted,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Logout Action
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await authVm.logout();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        AppRouter.scaleRoute(const RoleSelectionScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  label: Text(
                    'Logout / Switch Account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
